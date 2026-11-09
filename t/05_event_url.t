use strict;
use Test::More 0.98;
use URI;
use WebService::Mailgun;

# This test never reaches a real API server: the HTTP client is replaced with one that records
# the URLs it is asked for and answers every request with an empty page of events.
{
    package t::Client;
    sub new { bless { urls => [] }, shift }
    sub get {
        my ($self, $url) = @_;
        push @{ $self->{urls} }, $url;
        return t::Response->new;
    }

    package t::Response;
    sub new        { bless {}, shift }
    sub is_success { 1 }
    sub content {
        '{"items":[],"paging":{"previous":"https://api.mailgun.net/v3/example.com/events/previous-page"}}';
    }
}

my $mailgun = WebService::Mailgun->new(
    api_key => 'dummy-api-key',
    domain  => 'example.com',
);
my $client = t::Client->new;
$mailgun->{_client} = $client;

my ($events, $purl) = $mailgun->event({ event => 'stored' });

is_deeply $events, [], 'no events';
is $client->{urls}[0],
    'https://api:dummy-api-key@api.mailgun.net/v3/example.com/events?event=stored',
    'the query goes into the events URL';
isa_ok $purl, 'URI';
is "$purl", 'https://api:dummy-api-key@api.mailgun.net/v3/example.com/events/previous-page',
    'the previous URL carries the API key';

subtest 'event($purl) fetches the URL it is given' => sub {
    @{ $client->{urls} } = ();
    $purl->userinfo(undef);
    $mailgun->event($purl);
    is $client->{urls}[0],
        'https://api:dummy-api-key@api.mailgun.net/v3/example.com/events/previous-page';
    is "$purl", 'https://api.mailgun.net/v3/example.com/events/previous-page',
        'the URI passed in is left as it is';
};

subtest 'the API key goes only to the API host over https' => sub {
    for my $url (
        'https://evil.example.com/v3/example.com/events/previous-page',
        'http://api.mailgun.net/v3/example.com/events/previous-page',
        'events/previous-page',
        '',
    ) {
        @{ $client->{urls} } = ();
        eval { $mailgun->event($url) };
        like $@, qr/^event\(\) takes a query hash reference or an https URL on api\.mailgun\.net/,
            "'$url' is refused";
        is scalar @{ $client->{urls} }, 0, 'nothing is requested';
    }
};

subtest 'a URL given as a string gets the API key' => sub {
    @{ $client->{urls} } = ();
    $mailgun->event('https://api.mailgun.net/v3/example.com/events/previous-page');
    is $client->{urls}[0],
        'https://api:dummy-api-key@api.mailgun.net/v3/example.com/events/previous-page';
};

done_testing;
