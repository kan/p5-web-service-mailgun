use strict;
use warnings;
use Test::More 0.98;
use File::Temp;
use WebService::Mailgun;

# This test never reaches a real API server: the HTTP client is replaced with one that keeps
# the request it is given and answers with an empty success.
{
    package t::Client;
    sub new     { bless {}, shift }
    sub request { $_[0]{request} = $_[1]; t::Response->new }

    package t::Response;
    sub new         { bless {}, shift }
    sub is_success  { 1 }
    sub status_line { '200 OK' }
    sub content     { '{"id":"<1@example.com>","message":"Queued. Thank you."}' }
}

my $mailgun = WebService::Mailgun->new(
    api_key => 'dummy-api-key',
    domain  => 'example.com',
);
my $client = t::Client->new;
$mailgun->{_client} = $client;

# The form fields of the request, in order, as [name, value, filename].
sub fields {
    my $req = $client->{request};
    my ($boundary) = $req->header('Content-Type') =~ /boundary="?([^";]+)"?/;
    my @parts = split /--\Q$boundary\E(?:--)?\r\n/, $req->content;
    my @fields;
    for my $part (grep { length } @parts) {
        my ($head, $body) = split /\r\n\r\n/, $part, 2;
        my ($name)     = $head =~ /name="([^"]*)"/;
        my ($filename) = $head =~ /filename="([^"]*)"/;
        $body =~ s/\r\n\z//;
        push @fields, [ $name, $body, $filename ];
    }
    return @fields;
}

sub values_of {
    my ($name, @fields) = @_;
    return [ map { $_->[1] } grep { $_->[0] eq $name } @fields ];
}

subtest 'an array of values in a hash reference sends the key once for each' => sub {
    my $res = eval {
        $mailgun->message({
            from    => 'foo@example.com',
            to      => [ 'a@example.com', 'b@example.com' ],
            'o:tag' => [ 'x', 'y' ],
            text    => 'text',
        });
    };
    is $@, '', 'does not die';
    ok $res, 'returns the response';
    my @fields = fields();
    is_deeply values_of(to => @fields), [ 'a@example.com', 'b@example.com' ];
    is_deeply values_of('o:tag' => @fields), [ 'x', 'y' ];
    is_deeply values_of(from => @fields), ['foo@example.com'], 'a plain value as before';
};

subtest 'the same in an array reference of pairs' => sub {
    $mailgun->message([ from => 'foo@example.com', to => [ 'a@example.com', 'b@example.com' ], to => 'c@example.com' ]);
    is_deeply values_of(to => fields()), [ 'a@example.com', 'b@example.com', 'c@example.com' ];
};

subtest 'attachment and inline still take an array reference as a file' => sub {
    my $file = File::Temp->new;
    print $file 'PDF';
    close $file;
    $mailgun->message([
        from       => 'foo@example.com',
        to         => 'a@example.com',
        attachment => [ $file->filename, 'a.pdf' ],
        inline     => [ $file->filename, 'b.png' ],
    ]);
    my %by_name = map { $_->[0] => $_ } fields();
    is $by_name{attachment}[2], 'a.pdf', 'attachment is a file';
    is $by_name{attachment}[1], 'PDF', 'with its content';
    is $by_name{inline}[2], 'b.png', 'inline is a file';
};

subtest 'several files in a hash reference' => sub {
    my $file = File::Temp->new;
    print $file 'PDF';
    close $file;
    $mailgun->message({
        from       => 'foo@example.com',
        to         => 'a@example.com',
        attachment => [ [ $file->filename, 'a.pdf' ], [ $file->filename, 'b.pdf' ] ],
    });
    is_deeply [ map { $_->[2] } grep { $_->[0] eq 'attachment' } fields() ], [ 'a.pdf', 'b.pdf' ];
};

subtest 'an empty array reference dies before any request' => sub {
    delete $client->{request};
    eval { $mailgun->message({ from => 'foo@example.com', to => [], text => 'text' }) };
    like $@, qr/^message\(\): 'to' is an empty array reference/;
    ok !$client->{request}, 'nothing is requested';
};

done_testing;
