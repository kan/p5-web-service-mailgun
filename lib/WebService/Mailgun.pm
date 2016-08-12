package WebService::Mailgun;
use 5.008001;
use strict;
use warnings;

use Furl;
use JSON::XS;

our $VERSION = "0.01";
our $API_BASE = 'api.mailgun.net/v3';

use Class::Accessor::Lite (
    new => 1,
    rw  => [qw(api_key domain)],
);

sub client {
    my $self = shift;

    $self->{_client} //= Furl->new(
        agent => __PACKAGE__ . '/' . $VERSION,
    );
}

sub api_url {
    my ($self, $method) = @_;

    sprintf 'https://api:%s@%s/%s/%s',
        $self->api_key, $API_BASE, $self->domain, $method;
}

sub message {
    my ($self, $args) = @_;

    my $res = $self->client->post($self->api_url('messages'), [], $args);
    if ($res->is_success) {
        return decode_json $res->content;
    } else {
        my $json = decode_json $res->content;
        warn $json->{message};
        die $res->status_line;
    }
}


1;
__END__

=encoding utf-8

=head1 NAME

WebService::Mailgun - It's new $module

=head1 SYNOPSIS

    use WebService::Mailgun;

=head1 DESCRIPTION

WebService::Mailgun is ...

=head1 LICENSE

Copyright (C) Kan Fushihara.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kan Fushihara E<lt>kan.fushihara@gmail.comE<gt>

=cut

