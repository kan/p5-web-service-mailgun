use strict;
use Test::More 0.98;
use Test::Exception;
use WebService::Mailgun;
use JSON::XS;

my $mailgun = WebService::Mailgun->new(
    api_key => 'key-389807c554fdfe0a7757adf0650f7768',
    domain  => 'sandbox56435abd76e84fa6b03de82540e11271.mailgun.org',
    RaiseError => 1,
);

subtest 'get events' => sub {
    ok my $res = $mailgun->event({
    });
    note explain $res;
    use Data::Dumper;
    warn Dumper($res);
};

done_testing;
