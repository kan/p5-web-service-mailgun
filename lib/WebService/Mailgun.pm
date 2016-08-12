package WebService::Mailgun;
use 5.008001;
use strict;
use warnings;

use Furl;
use JSON::XS;
use URI;

our $VERSION = "0.01";
our $API_BASE = 'api.mailgun.net/v3';

use Class::Accessor::Lite (
    new => 1,
    rw  => [qw(api_key domain)],
);

sub decode_response ($) {
    my $res = shift;

    if ($res->is_success) {
        return decode_json $res->content;
    } else {
        my $json = decode_json $res->content;
        warn $json->{message};
        die $res->status_line;
    }
}

sub client {
    my $self = shift;

    $self->{_client} //= Furl->new(
        agent => __PACKAGE__ . '/' . $VERSION,
    );
}

sub api_url {
    my ($self, $method) = @_;

    sprintf 'https://api:%s@%s/%s',
        $self->api_key, $API_BASE, $method;
}

sub domain_api_url {
    my ($self, $method) = @_;

    sprintf 'https://api:%s@%s/%s/%s',
        $self->api_key, $API_BASE, $self->domain, $method;
}

sub message {
    my ($self, $args) = @_;

    my $res = $self->client->post($self->domain_api_url('messages'), [], $args);
    decode_response $res;
}

sub lists {
    my $self = shift;
    my $query = '';
    my @result;

    while (1) {
        my $api_uri = URI->new($self->api_url('lists/pages'));
        $api_uri->query($query);
        my $res = $self->client->get($api_uri->as_string);
        my $json = decode_response $res;
        last unless scalar @{$json->{items}};
        push @result, @{$json->{items}};
        my $next_uri = URI->new($json->{paging}->{next});
        $query = $next_uri->query;
    }

    return \@result;
}

sub add_list {
    my ($self, $args) = @_;

    my $res = $self->client->post($self->api_url("lists"), [], $args);
    decode_response $res;
}

sub list {
    my ($self, $address) = @_;

    my $res = $self->client->get($self->api_url("lists/$address"));
    decode_response $res;
}

sub update_list {
    my ($self, $address, $args) = @_;

    my $res = $self->client->put($self->api_url("lists/$address"), [], $args);
    decode_response $res;
}

sub delete_list {
    my ($self, $address) = @_;

    my $res = $self->client->delete($self->api_url("lists/$address"));
    decode_response $res;
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

