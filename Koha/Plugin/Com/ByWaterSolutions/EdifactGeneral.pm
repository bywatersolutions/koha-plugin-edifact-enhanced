package Koha::Plugin::Com::ByWaterSolutions::EdifactGeneral;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Branch;
use C4::Members;
use C4::Auth;

## Here we set our plugin version
our $VERSION = 1.00;

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name   => 'Edifact Enhanced',
    author => 'Kyle M Hall',
    description => 'This plugin replicates the basic Edifact functionality with more options.',
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

## The existance of an 'edifact' subroutine means the plugin is capable
## of running replacing the default Edifact modules for generated Edifcat messages
sub edifact {
    my ( $self, $args ) = @_;

    require Koha::Plugin::Com::ByWaterSolutions::EdifactGeneral::Edifact::Order;

    $args->{params}->{plugin} = $self;
    my $edifact_order = Koha::Plugin::Com::ByWaterSolutions::EdifactGeneral::Edifact::Order->new( $args->{params} );
    return $edifact_order;
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
