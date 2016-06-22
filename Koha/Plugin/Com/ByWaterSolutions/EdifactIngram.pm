package Koha::Plugin::Com::ByWaterSolutions::EdifactIngram;

## It's good practive to use Modern::Perl
use Modern::Perl;

use Carp;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Branch;
use C4::Members;
use C4::Auth;
use C4::Biblio;
use C4::Items;
use Koha::EDI;
use Koha::DateUtils;

## Here we set our plugin version
our $VERSION = 1.00;

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name   => 'Edifact Ingram',
    author => 'Kyle M Hall',
    description => 'Edifact Enhanced plugin customized for Ingram',
    date_authored   => '2015-12-21',
    date_updated    => '2015-12-21',
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
    
    require Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact;

    my $edifact = Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact->new( $args );
    return $edifact;
}

sub edifact_order {
    my ( $self, $args ) = @_;
    
    require Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact::Order;

    $args->{params}->{plugin} = $self;
    my $edifact_order = Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact::Order->new( $args->{params} );
    return $edifact_order;
}

sub edifact_transport {
    my ( $self, $args ) = @_;
    
    require Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact::Transport;

    $args->{params}->{plugin} = $self;

    my $edifact_transport = Koha::Plugin::Com::ByWaterSolutions::EdifactIngram::Edifact::Transport->new( $args->{vendor_edi_account_id} );

    return $edifact_transport;
}

sub edifact_process_invoice {
    my ( $self, $args ) = @_;
    my $invoice_message = $args->{invoice};
warn "INVOICE: $invoice_message";
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
warn "INVOICE: $invoicenumber";
            my $shipmentcharge = $msg->shipment_charge();
warn "SHIPMENT CHARGE: $shipmentcharge";
            my $msg_date       = $msg->message_date;
warn "MSG DATE: $msg_date";
            my $tax_date       = $msg->tax_point_date;
warn "TAX DATE: $tax_date";
            if ( !defined $tax_date || $tax_date !~ m/^\d{8}/xms ) {
                $tax_date = $msg_date;
            }

            my $vendor_ean = $msg->supplier_ean;
warn "VENDOR EAN: $vendor_ean";
            if ( !defined $vendor_acct || $vendor_ean ne $vendor_acct->san ) {
                $vendor_acct = $schema->resultset('VendorEdiAccount')->search(
                    {
                        san => $vendor_ean,
                    }
                )->single;
            }
            if ( !$vendor_acct ) {
                carp "Cannot find vendor with ean $vendor_ean for invoice $invoicenumber in $invoice_message->filename";
                next;
            }
            $invoice_message->edi_acct( $vendor_acct->id );
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
            my $lines = $msg->lineitems();

            foreach my $line ( @{$lines} ) {
                my $ordernumber = $line->ordernumber;
warn "ORDERNUMBER: $ordernumber";
                $logger->trace( "Receipting order:$ordernumber Qty: ",
                    $line->quantity );

                my $order = $schema->resultset('Aqorder')->find($ordernumber);
warn "ORDER: $order";

      # ModReceiveOrder does not validate that $ordernumber exists validate here
                if ($order) {

                    # check suggestions
                    my $s = $schema->resultset('Suggestion')->search(
                        {
                            biblionumber => $order->biblionumber->biblionumber,
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
warn "PRICE: $price";
warn "ORDER QTY: " . $order->quantity;
warn "LINE QTY: " . $line->quantity;

                    if ( $order->quantity > $line->quantity ) {
                        my $ordered = $order->quantity;

                        # part receipt
                        $order->orderstatus('partial');
                        $order->quantity( $ordered - $line->quantity );
                        $order->update;
                        my $received_order = $order->copy(
                            {
                                ordernumber      => undef,
                                quantity         => $line->quantity,
                                quantityreceived => $line->quantity,
                                orderstatus      => 'complete',
                                unitprice        => $price,
                                invoiceid        => $invoiceid,
                                datereceived     => $msg_date,
                            }
                        );
                        #FIXME transfer_items( $schema, $line, $order, $received_order );
                        _receipt_items( $schema, $line, $received_order->ordernumber );
                    }
                    else {    # simple receipt all copies on order
                        $order->quantityreceived( $line->quantity );
                        $order->datereceived($msg_date);
                        $order->invoiceid($invoiceid);
                        $order->unitprice($price);
                        $order->orderstatus('complete');
                        $order->update;
                        _receipt_items( $schema, $line, $ordernumber );
                    }
                }
                else {
                    $logger->error(
                        "No order found for $ordernumber Invoice:$invoicenumber"
                    );
                    next;
                }

            }

        }
    }

    $invoice_message->status('received');
    $invoice_message->update;    # status and basketno link
    return;
}

sub _receipt_items {
    my ( $schema, $inv_line, $ordernumber ) = @_;
    my $logger   = Log::Log4perl->get_logger();
    my $quantity = $inv_line->quantity;

    # itemnumber is not a foreign key ??? makes this a bit cumbersome
    my @order_items = $schema->resultset('AqordersItem')->search(
        {
            ordernumber => $ordernumber,
        }
    );

    my $items_recieved_count = 0;

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

       # Cost, normal purchase price, i.e. actual paid price
       $item->price( $order->unitprice() );

       # Cost, replacement price
       $item->replacementprice( $order->rrp() );

       # Price effective from
       $item->replacementpricedate( dt_from_string() );

       # Note that this was recieved via EDI
       $item->itemnotes_nonpublic( "Recieved via EDIFACT" );

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

       $items_recieved_count++;
       last if $items_recieved_count == $quantity; 
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
            lin_use_ean       => $self->retrieve_data('lin_use_ean'),
            lin_use_issn      => $self->retrieve_data('lin_use_issn'),
            lin_use_isbn      => $self->retrieve_data('lin_use_isbn'),
            pia_use_ean       => $self->retrieve_data('pia_use_ean'),
            pia_use_issn      => $self->retrieve_data('pia_use_issn'),
            pia_use_isbn10    => $self->retrieve_data('pia_use_isbn10'),
            pia_use_isbn13    => $self->retrieve_data('pia_use_isbn13'),
            order_file_suffix => $self->retrieve_data('order_file_suffix'),
            buyer_san         => $self->retrieve_data('buyer_san'),
            buyer_id_code_qualifier =>
              $self->retrieve_data('buyer_id_code_qualifier'),
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                lin_use_ean    => $cgi->param('lin_use_ean')    ? 1 : 0,
                lin_use_issn   => $cgi->param('lin_use_issn')   ? 1 : 0,
                lin_use_isbn   => $cgi->param('lin_use_isbn')   ? 1 : 0,
                pia_use_ean    => $cgi->param('pia_use_ean')    ? 1 : 0,
                pia_use_issn   => $cgi->param('pia_use_issn')   ? 1 : 0,
                pia_use_isbn10 => $cgi->param('pia_use_isbn10') ? 1 : 0,
                pia_use_isbn13 => $cgi->param('pia_use_isbn13') ? 1 : 0,
                order_file_suffix => $cgi->param('order_file_suffix'),
                buyer_san         => $cgi->param('buyer_san'),
                buyer_id_code_qualifier =>
                  $cgi->param('buyer_id_code_qualifier'),
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
