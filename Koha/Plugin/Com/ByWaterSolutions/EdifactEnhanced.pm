package Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;

## It's good practive to use Modern::Perl
use Modern::Perl;

use Carp;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Members;
use C4::Auth;
use C4::Biblio;
use C4::Items;
use Koha::EDI;
use Koha::DateUtils;

## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name   => 'Edifact - Ingram',
    author => 'Kyle M Hall',
    description => 'Edifact Enhanced plugin customized for Ingram',
    date_authored   => '2015-12-21',
    date_updated    => '1900-01-01',
    minimum_version => undef,
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'edifact' subroutine means the plugin is capable
## of running replacing the default Edifact modules for generated Edifcat messages
sub edifact {
    my ( $self, $args ) = @_;

    require Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact;

    my $edifact = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact->new( $args );
    return $edifact;
}

sub edifact_order {
    my ( $self, $args ) = @_;

    require Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order;

    $args->{params}->{plugin} = $self;
    my $edifact_order = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order->new( $args->{params} );
    return $edifact_order;
}

sub edifact_transport {
    my ( $self, $args ) = @_;

    require Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Transport;

    $args->{params}->{plugin} = $self;

    my $edifact_transport = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Transport->new( $args->{vendor_edi_account_id}, $self );

    return $edifact_transport;
}

sub edifact_process_invoice {
    my ( $self, $args ) = @_;
    my $invoice_message = $args->{invoice};
    $invoice_message->status('processing');
    $invoice_message->update;
    my $schema = Koha::Database->new()->schema();
    my $logger = Log::Log4perl->get_logger();
    my $vendor_acct;

    my $plugin = $invoice_message->edi_acct()->plugin();
    my $edi_plugin;
    if ( $plugin ) {
        $edi_plugin = Koha::Plugins::Handler->run(
            {
                class  => $plugin,
                method => 'edifact',
                params => {
                    invoice_message => $invoice_message,
                    transmission => $invoice_message->raw_msg,
                }
            }
        );
    }

    my $edi = $edi_plugin ||
      Koha::Edifact->new( { transmission => $invoice_message->raw_msg, } );

    my $messages = $edi->message_array();

    if ( @{$messages} ) {

        # BGM contains an invoice number
        foreach my $msg ( @{$messages} ) {
            my $invoicenumber  = $msg->docmsg_number();
            my $shipmentcharge = $msg->shipment_charge( $self );
            my $msg_date       = $msg->message_date;
            my $tax_date       = $msg->tax_point_date;
            if ( !defined $tax_date || $tax_date !~ m/^\d{8}/xms ) {
                $tax_date = $msg_date;
            }

## This method is proved to be highly unreliable. We should get the vendor from the edifact_messages column vendor_id
## and limit our search for ordernumbers to that vendor
#            my $vendor_ean = $msg->supplier_ean;
#            if ( !defined $vendor_acct || $vendor_ean ne $vendor_acct->san ) {
#                $vendor_acct = $schema->resultset('VendorEdiAccount')->search(
#                    {
#                        san => $vendor_ean,
#                    }
#                )->single;
#            }
#            if ( !$vendor_acct ) {
#                carp "Cannot find vendor with ean $vendor_ean for invoice $invoicenumber in $invoice_message->filename";
#                next;
#            }
#            $invoice_message->edi_acct( $vendor_acct->id );

            my $vendor_acct = $invoice_message->edi_acct();

            $logger->trace("Adding invoice:$invoicenumber");
            my $new_invoice = $schema->resultset('Aqinvoice')->create(
                {
                    invoicenumber         => $invoicenumber,
                    booksellerid          => $invoice_message->vendor_id,
                    shipmentdate          => $msg_date,
                    billingdate           => $tax_date,
                    shipmentcost          => $shipmentcharge,
                    shipmentcost_budgetid => $vendor_acct->shipment_budget,
                    message_id            => $invoice_message->id,
                }
            );
            my $invoiceid = $new_invoice->invoiceid;
            $logger->trace("Added as invoiceno :$invoiceid");
            warn("Added as invoice id: $invoiceid");
            my $lines = $msg->lineitems();

            foreach my $line ( @{$lines} ) {
                my $ordernumber = $line->ordernumber;
                warn "ORDER NUMBER: $ordernumber";
                $logger->trace( "Receipting order:$ordernumber Qty: ",
                    $line->quantity );

                my $order = $schema->resultset('Aqorder')->find($ordernumber);
                unless ( $order ) {
                    warn "No order found for order number $ordernumber, the vendor is probably sending the wrong value in the RFF+LI segment.";
                    $logger->error("No order found for order number $ordernumber, the vendor is probably sending the wrong value in the RFF+LI segment.");
                    next;
                }

                my $biblio = $order->biblionumber();
                unless ( $biblio ) {
                    warn "No record found for order $ordernumber, record probably deleted";
                    $logger->error("No record found for order $ordernumber, record probably deleted");
                    next;
                }

                my $vendor_id = $invoice_message->vendor_id();
                my $basket_vendor_id = $order->basketno()->get_column('booksellerid');
                if ( $basket_vendor_id ne $vendor_id ) {
                    $logger->error("The order found for order number $ordernumber is valid, but the vendor for that order does not match the vendor that sent the invoice.");

                    my $edi_vendor = $schema->resultset('VendorEdiAccount')->find({ vendor_id => $vendor_id});
                    next unless $edi_vendor;

                    my $basket_vendor = $schema->resultset('VendorEdiAccount')->find({ vendor_id => $basket_vendor_id });
                    next unless $basket_vendor;

                    # This is necessary because some libraries use the same plugin for multiple "vendors" that are really the same vendor.
                    # Because of this, the first edi vendor instance will pick up all the invoices for all the different instances.
                    # So as long as they share the same plugin, we should allow the item to be received
                    if ( $edi_vendor->plugin eq $basket_vendor->plugin ) {
                        $logger->error("The plugin used by the vendor is the same as that used by the basket, allow it. PLUGIN: " . $edi_vendor->plugin );
                    } else {
                        next;
                    }
                }

                # ModReceiveOrder does not validate that $ordernumber exists validate here
                if ($order) {
                    $new_invoice->shipmentcost_budgetid( $order->budget_id ) if $self->retrieve_data('ship_budget_from_orderline');

                    # check suggestions
                    my $s = $schema->resultset('Suggestion')->search(
                        {
                            biblionumber => $biblio->biblionumber,
                        }
                    )->single;
                    if ($s) {
                        ModSuggestion(
                            {
                                suggestionid => $s->suggestionid,
                                STATUS       => 'AVAILABLE',
                            }
                        );
                    }

                    my $price = Koha::EDI::_get_invoiced_price($line);

                    my $basket = $order->aqbasket;
                    my $is_standing = $basket->is_standing;

                    if ( $is_standing || $order->quantity > $line->quantity ) {
                        my $ordered = $order->quantity;

                        my $quantity_remaining = $is_standing ? 1 : $ordered - $line->quantity;

                        # part receipt
                        $order->orderstatus('partial');
                        $order->quantity( $quantity_remaining );
                        $order->update;
                        my $received_order = $order->copy(
                            {
                                ordernumber      => undef,
                                quantity         => $line->quantity || 1,
                                quantityreceived => $line->quantity || 1,
                                orderstatus      => 'complete',
                                unitprice        => $price,
                                invoiceid        => $invoiceid,
                                datereceived     => $msg_date,
                            }
                        );
                        #FIXME transfer_items( $schema, $line, $order, $received_order );
                        _receipt_items( $self, $schema, $line, $received_order->ordernumber );
                    }
                    else {    # simple receipt all copies on order
                        $order->quantityreceived( $line->quantity );
                        $order->datereceived($msg_date);
                        $order->invoiceid($invoiceid);
                        $order->unitprice($price);
                        eval { $order->unitprice_tax_excluded($price); }; # doesn't work in 3.22
                        eval { $order->unitprice_tax_included($price); }; # doesn't work in 3.22
                        $order->orderstatus('complete');
                        $order->update;
                        _receipt_items( $self, $schema, $line, $ordernumber );
                    }
                }
                else {
                    $logger->error(
                        "No order found for $ordernumber Invoice:$invoicenumber"
                    );
                    next;
                }

            }

            my $now = dt_from_string();
            $new_invoice->closedate( $now->ymd() ) if $self->retrieve_data('close_invoice_on_receipt');
            $new_invoice->update(); # shipment budgetid may have been updated

        }
    }

    $invoice_message->status('received');
    $invoice_message->update;    # status and basketno link
    return;
}

sub _receipt_items {
    my ( $self, $schema, $inv_line, $ordernumber ) = @_;
    my $logger   = Log::Log4perl->get_logger();
    my $quantity = $inv_line->quantity;

    # itemnumber is not a foreign key ??? makes this a bit cumbersome
    my @order_items = $schema->resultset('AqordersItem')->search(
        {
            ordernumber => $ordernumber,
        }
    );

    my $items_received_count = 0;

    foreach my $order_item ( @order_items ) {
       my $item = $schema->resultset('Item')->find( $order_item->itemnumber() );
       unless ( $item ) {
           carp("No item found for order line $ordernumber!");
           next;
       }

       my $order = $order_item->ordernumber();
       my $basket = $order->basketno();
       my $bookseller = $basket->booksellerid();

       # Date aquired
       $item->dateaccessioned( dt_from_string() );

       # Source of acquisition, i.e. Vendor ID
       $item->booksellerid( $bookseller->id() );

       my $update_item_price = $self->retrieve_data('no_update_item_price');
       $update_item_price = 'update_both'    if $update_item_price eq '0';
       $update_item_price = 'update_neither' if $update_item_price eq '1';
       if ( $update_item_price eq 'update_both' || $update_item_price eq 'update_price' ) {
           # Cost, normal purchase price, i.e. actual paid price
           $item->price( $order->unitprice() );
       }
       if ( $update_item_price eq 'update_both' || $update_item_price eq 'update_replacementprice' ) {
           # Cost, replacement price
           $item->replacementprice( $order->rrp() );

           # Price effective from
           $item->replacementpricedate( dt_from_string() );
       }

       my $set_nfl_on_receipt = $self->retrieve_data('set_nfl_on_receipt');
       if ( defined( $set_nfl_on_receipt ) && $set_nfl_on_receipt ne q{} ) {
           $item->notforloan( $set_nfl_on_receipt );
       }

       # Note that this was received via EDI
       if ( $self->retrieve_data('add_itemnote_on_receipt') ) {
           $item->itemnotes_nonpublic( "Received via EDIFACT" );
       }

       $item->update();

       my $biblionumber = $item->get_column('biblionumber');
       my $itemnumber   = $item->id();
       if ( C4::Context->preference('AcqCreateItem') eq 'ordering' ) {
           my @affects = split q{\|}, C4::Context->preference("AcqItemSetSubfieldsWhenReceived");
           if ( @affects ) {
               my $frameworkcode = GetFrameworkCode($biblionumber);
               my ( $itemfield ) = GetMarcFromKohaField( 'items.itemnumber', $frameworkcode );
               my $item_marc = C4::Items::GetMarcItem( $biblionumber, $itemnumber );
               for my $affect ( @affects ) {
                   my ( $sf, $v ) = split q{=}, $affect, 2;

                   foreach ( $item_marc->field($itemfield) ) {
                       $_->update( $sf => $v );
                   }
               }

               C4::Items::ModItemFromMarc( $item_marc, $biblionumber, $itemnumber );
           }
       }

       $items_received_count++;
       last if $items_received_count == $quantity; 
    }
}

## If your tool is complicated enough to needs it's own setting/configuration
## you will want to add a 'configure' method to your plugin like so.
## Here I am throwing all the logic into the 'configure' method, but it could
## be split up like the 'report' method is.
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            lin_use_ean             => $self->retrieve_data('lin_use_ean'),
            lin_use_issn            => $self->retrieve_data('lin_use_issn'),
            lin_use_isbn            => $self->retrieve_data('lin_use_isbn'),
            lin_force_first_isbn    => $self->retrieve_data('lin_force_first_isbn'),
            lin_use_invalid_isbn13  => $self->retrieve_data('lin_use_invalid_isbn13'),
            lin_use_invalid_isbn_any=> $self->retrieve_data('lin_use_invalid_isbn_any'),
            lin_use_upc             => $self->retrieve_data('lin_use_upc'),
            lin_use_product_id      => $self->retrieve_data('lin_use_product_id'),
            pia_send_lin            => $self->retrieve_data('pia_send_lin'),
            pia_limit               => $self->retrieve_data('pia_limit'),
            pia_use_ean             => $self->retrieve_data('pia_use_ean'),
            pia_use_issn            => $self->retrieve_data('pia_use_issn'),
            pia_use_isbn10          => $self->retrieve_data('pia_use_isbn10'),
            pia_use_isbn13          => $self->retrieve_data('pia_use_isbn13'),
            pia_use_upc             => $self->retrieve_data('pia_use_upc'),
            pia_use_product_id      => $self->retrieve_data('pia_use_product_id'),
            order_file_suffix       => $self->retrieve_data('order_file_suffix'),
            invoice_file_suffix     => $self->retrieve_data('invoice_file_suffix'),
            buyer_san               => $self->retrieve_data('buyer_san'),
            buyer_san_use_username  => $self->retrieve_data('buyer_san_use_username'),
            buyer_san_use_library_ean_split_first_part  => $self->retrieve_data('buyer_san_use_library_ean_split_first_part'),
            gir_mapping             => $self->retrieve_data('gir_mapping'),
            gir_disable             => $self->retrieve_data('gir_disable'),
            send_basketname         => $self->retrieve_data('send_basketname'),
            send_rff_bfn            => $self->retrieve_data('send_rff_bfn'),
            split_gir               => $self->retrieve_data('split_gir') // '4',
            buyer_id_code_qualifier => $self->retrieve_data('buyer_id_code_qualifier'),
            buyer_san_in_header     => $self->retrieve_data('buyer_san_in_header'),
            buyer_san_in_nadby      => $self->retrieve_data('buyer_san_in_nadby'),
            branch_ean_in_header    => $self->retrieve_data('branch_ean_in_header'),
            branch_ean_in_nadby     => $self->retrieve_data('branch_ean_in_nadby'),
            ship_budget_from_orderline => $self->retrieve_data('ship_budget_from_orderline'),
            shipment_charges_alc_dl    => $self->retrieve_data('shipment_charges_alc_dl'),
            shipment_charges_moa_8     => $self->retrieve_data('shipment_charges_moa_8'),
            shipment_charges_moa_124   => $self->retrieve_data('shipment_charges_moa_124'),
            shipment_charges_moa_131   => $self->retrieve_data('shipment_charges_moa_131'),
            shipment_charges_moa_304   => $self->retrieve_data('shipment_charges_moa_304'),
            close_invoice_on_receipt   => $self->retrieve_data('close_invoice_on_receipt'),
            add_itemnote_on_receipt    => $self->retrieve_data('add_itemnote_on_receipt'),
            no_update_item_price       => $self->retrieve_data('no_update_item_price'),
            set_nfl_on_receipt         => $self->retrieve_data('set_nfl_on_receipt') // q{},
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                lin_use_ean        => $cgi->param('lin_use_ean')        ? 1 : 0,
                lin_use_issn       => $cgi->param('lin_use_issn')       ? 1 : 0,
                lin_use_isbn       => $cgi->param('lin_use_isbn')       ? 1 : 0,
                lin_force_first_isbn => $cgi->param('lin_force_first_isbn') ? 1 : 0,
                lin_use_invalid_isbn13 => $cgi->param('lin_use_invalid_isbn13') ? 1 : 0,
                lin_use_invalid_isbn_any => $cgi->param('lin_use_invalid_isbn_any') ? 1 : 0,
                lin_use_upc        => $cgi->param('lin_use_upc')        ? 1 : 0,
                lin_use_product_id => $cgi->param('lin_use_product_id') ? 1 : 0,
                pia_send_lin       => $cgi->param('pia_send_lin')      ? 1 : 0,
                pia_use_ean        => $cgi->param('pia_use_ean')        ? 1 : 0,
                pia_use_issn       => $cgi->param('pia_use_issn')       ? 1 : 0,
                pia_use_isbn10     => $cgi->param('pia_use_isbn10')     ? 1 : 0,
                pia_use_isbn13     => $cgi->param('pia_use_isbn13')     ? 1 : 0,
                pia_use_upc        => $cgi->param('pia_use_upc')        ? 1 : 0,
                pia_use_product_id => $cgi->param('pia_use_product_id') ? 1 : 0,
                send_basketname    => $cgi->param('send_basketname')    ? 1 : 0,
                send_rff_bfn       => $cgi->param('send_rff_bfn')    ? 1 : 0,
                gir_disable        => $cgi->param('gir_disable')        ? 1 : 0,
                order_file_suffix  => $cgi->param('order_file_suffix') || q{},
                invoice_file_suffix => $cgi->param('invoice_file_suffix') || q{},
                buyer_san           => $cgi->param('buyer_san') || q{},
                buyer_san_use_username => $cgi->param('buyer_san_use_username') ? 1 : 0,
                buyer_san_use_library_ean_split_first_part => $cgi->param('buyer_san_use_library_ean_split_first_part') ? 1 : 0,
                gir_mapping         => $cgi->param('gir_mapping') || q{},
                split_gir           => $cgi->param('split_gir') || '0',
                buyer_id_code_qualifier => $cgi->param('buyer_id_code_qualifier') || q{},
                buyer_san_in_header     => $cgi->param('buyer_san_in_header')  ? 1 : 0,
                buyer_san_in_nadby      => $cgi->param('buyer_san_in_nadby')   ? 1 : 0,
                branch_ean_in_header    => $cgi->param('branch_ean_in_header') ? 1 : 0,
                branch_ean_in_nadby     => $cgi->param('branch_ean_in_nadby')  ? 1 : 0,
                ship_budget_from_orderline => $cgi->param('ship_budget_from_orderline') ? 1 : 0,
                shipment_charges_alc_dl    => $cgi->param('shipment_charges_alc_dl') ? 1 : 0,
                shipment_charges_moa_8     => $cgi->param('shipment_charges_moa_8') ? 1 : 0,
                shipment_charges_moa_124   => $cgi->param('shipment_charges_moa_124') ? 1 : 0,
                shipment_charges_moa_131   => $cgi->param('shipment_charges_moa_131') ? 1 : 0,
                shipment_charges_moa_304   => $cgi->param('shipment_charges_moa_304') ? 1 : 0,
                close_invoice_on_receipt   => $cgi->param('close_invoice_on_receipt')   ? 1 : 0,
                add_itemnote_on_receipt    => $cgi->param('add_itemnote_on_receipt')   ? 1 : 0,
                no_update_item_price       => $cgi->param('no_update_item_price'),
                set_nfl_on_receipt       => $cgi->param('set_nfl_on_receipt') // q{},
                pia_limit          => defined $cgi->param('pia_limit') ? $cgi->param('pia_limit') : undef,
            }
        );
        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

1;
