package WebService::Mailgun;


use 5.020;
use strict;
use warnings;

use Furl;
use JSON;
use URI;
use Try::Tiny;
use Carp;
use Scalar::Util qw(blessed);
use HTTP::Request::Common;
use File::Temp;


our $VERSION = "1.0.0";
our $API_BASE = 'api.mailgun.net/v3';
our $API_BASE_EU = 'api.eu.mailgun.net/v3';

use Class::Accessor::Lite (
    new => 1,
    rw  => [qw(api_key domain RaiseError region)],
    ro  => [qw(error error_status)],
);

# The body of a response as a hash reference, or undef when it is not a JSON object.
sub _json_object {
    my ($res) = @_;

    my $json = try { decode_json $res->content };
    return ref $json eq 'HASH' ? $json : undef;
}

sub decode_response {
    my ($self, $res) = @_;

    # Every endpoint answers with a JSON object. A success that is not one (a page from a proxy,
    # say) is a failure too, so that RaiseError decides whether it dies, as for any other (#35).
    # An empty body (204 No Content) is a success with nothing in it. The body goes into the
    # message cut short: a proxy's HTML page would otherwise fill the logs.
    if ($res->is_success) {
        my $content = $res->content // '';
        return {} if $content eq '';
        my $json = _json_object($res);
        return $json if $json;
        my $start = length $content > 200 ? substr($content, 0, 200) . '...' : $content;
        return $self->_fail("the response is not a JSON object: $start", $res->status_line);
    }

    my $json = _json_object($res);
    my $message = $json && defined $json->{message} && !ref $json->{message}
        ? $json->{message} : $res->content;
    return $self->_fail($message, $res->status_line);
}

# Records a failure in error and error_status, and dies with RaiseError. Without it, returns
# nothing, like the methods do on a failure.
sub _fail {
    my ($self, $message, $status_line) = @_;

    $self->{error} = $message;
    $self->{error_status} = $status_line;
    if ($self->RaiseError) {
        carp $self->error;
        croak $self->error_status;
    }
    return;
}

sub recursive {
    my ($self, $method, $query, $key, $api_uri) = @_;

    $query //= {};
    $key //= 'items';
    my @result;
    my $next;
    unless($api_uri) {
        $api_uri = URI->new($self->api_url($method));
        $api_uri->query_form($query);
    }

    # The URLs fetched so far, without the API key: a paging.next that points back to one of them
    # would go round for ever (#35).
    my %seen;
    my $status_line;
    while (1) {
        my $plain = $api_uri->clone;
        $plain->userinfo(undef);
        if ($seen{"$plain"}++) {
            $self->_fail("paging.next points back to $plain", $status_line);
            $next = $api_uri;
            last;
        }
        my $res = $self->client->get($api_uri->as_string);
        $status_line = $res->status_line;
        my $json = $self->decode_response($res);
        # A page without the list of items is a failure, like a request that failed (#35).
        if ($json && ref $json->{$key} ne 'ARRAY') {
            $json = $self->_fail("the response has no '$key' list", $res->status_line);
        }
        unless ($json) {
            # The request failed: return the URL of the page that failed, so that the caller can
            # fetch the rest from there.
            $next = $api_uri;
            last;
        }
        push @result, @{$json->{$key}};
        my $page_next = ref $json->{paging} eq 'HASH' && $json->{paging}->{next};
        unless (scalar @{$json->{$key}} && $page_next) {
            # The end: an empty page, or one with no paging.next. paging.next of the empty page
            # is where the items that come later will be; for events this is how Event Polling
            # goes on (#25). paging.previous would point back over the last page and return it
            # again. A page with no paging.next gives its own URL instead, never undef: passed
            # back, `event(undef)` would fetch every event again.
            if ($page_next) {
                $next = URI->new($page_next);
                $next->userinfo('api:'.$self->api_key);
            } else {
                $next = $api_uri;
            }
            last;
        }
        $api_uri = URI->new($page_next);
        $api_uri->userinfo('api:'.$self->api_key);
    }

    return \@result, $next;
}

sub client {
    my $self = shift;

    $self->{_client} //= Furl->new(
        agent => __PACKAGE__ . '/' . $VERSION,
    );
}

sub api_base {
    my ($self) = @_;

    if ($self->region) {
        if (lc($self->region) eq "eu") {
            return $API_BASE_EU;
        } elsif (lc($self->region) ne "us") {
            die "unsupported region '" . $self->region ."'";
        }
    }
    return $API_BASE;
}

sub api_url {
    my ($self, $method) = @_;

    sprintf 'https://api:%s@%s/%s',
        $self->api_key, $self->api_base, $method;
}

sub domain_api_url {
    my ($self, $method) = @_;

    sprintf 'https://api:%s@%s/%s/%s',
        $self->api_key, $self->api_base, $self->domain, $method;
}

# The URL path from its segments, such as ('lists', $address, 'members'). Each segment (a list
# address, a member address, a template name) is percent-encoded on its own (#34). What a
# segment can hold as it is (the pchar of RFC 3986: `@`, `+` and the like) is left alone, so the
# addresses that worked before go out the same; `?`, `#`, `/`, `%` and the rest are encoded, so
# that they cannot end the path or add a segment.
#
# A decoded string (one with the UTF-8 flag) is sent as UTF-8. Any other string is taken as the
# bytes to send, as before, so that an address read without decoding is not encoded twice.
#
# An undefined or empty segment dies: `list(undef)` would otherwise ask for `lists`, every list.
sub _path {
    my @segments = @_;

    return join '/', map {
        croak 'an address or a name is required' unless defined $_ && length $_;
        my $segment = $_;
        utf8::encode($segment) if utf8::is_utf8($segment);
        $segment =~ s/([^A-Za-z0-9\-._~!\$&'()*+,;=:\@])/sprintf '%%%02X', ord $1/ge;
        $segment;
    } @segments;
}

# The keys of message() whose array reference is a file for HTTP::Request::Common
# ([$path, $filename, ...]). An array reference under any other key is a list of values.
my %FILE_KEYS = map { $_ => 1 } qw(attachment inline);

sub message {
    my ($self, $args) = @_;

    my @pairs;
    if (ref($args) eq 'HASH') {
        @pairs = %$args;
    }
    elsif (ref($args) eq 'ARRAY') {
        @pairs = @$args;
    }
    else {
        die 'unsupport argument. message() need HashRef or ArrayRef.';
	}

    # `to => ['a@example.com', 'b@example.com']` sends `to` twice, as Mailgun takes a key given
    # more than once. HTTP::Request::Common would take the array reference for a file, and die
    # opening a file named after the first address (#36).
    # Under attachment and inline, an array reference of array references is several files.
    my @content;
    for (my $i = 0; $i < @pairs; $i += 2) {
        my ($key, $value) = @pairs[$i, $i + 1];
        if (ref $value ne 'ARRAY') {
            push @content, $key => $value;
            next;
        }
        # An empty list would leave the key out, and Mailgun would answer that it is missing.
        croak "message(): '$key' is an empty array reference" unless @$value;
        if (!$FILE_KEYS{$key}) {
            push @content, map { ($key => $_) } @$value;
        } elsif (ref $value->[0] eq 'ARRAY') {
            push @content, map { ($key => $_) } @$value;
        } else {
            push @content, $key => $value;
        }
    }

    my $req = POST $self->domain_api_url('messages'), Content_type => 'form-data', Content => \@content;

    my $res = $self->client->request($req);
    $self->decode_response($res);
}



sub mime { 
		
    my ($self, $args) = @_;

    if (ref($args) eq 'HASH') {
        # Well, good!
    }
    else {
        die 'unsupport argument. mime() needs a hash ref.';
    }
	
	
	my $tmp = undef; 

	if(exists($args->{message})){
		$tmp = File::Temp->new();
		
		if(ref $args->{message} eq 'SCALAR'){ 
			# save from a ref
			print $tmp ${$args->{message}};
			seek $tmp, 0, 0;
		}
		else {
			# Save from a string
			print $tmp $args->{message};
			seek $tmp, 0, 0;
		}
		$args->{message} = [$tmp->filename];
	}
	elsif(exists($args->{file})){ 
		if(-f $args->{file}){ 
			$args->{message} =  [$args->{file}];
			delete $args->{file}; 
		}
		else { 
			die "cannot find file, " . $args->{file}; 
		}
	}
	
	# Put it back together: 
	my @content = %$args;

    my $req = POST $self->domain_api_url('messages.mime'), 
		Content_Type => 'form-data', 
		Content => \@content;
		
    my $res = $self->client->request($req);
	
	undef $tmp; 
	
    $self->decode_response($res);

}




sub lists {
    my $self = shift;

    return $self->recursive('lists/pages');
}

sub add_list {
    my ($self, $args) = @_;

    my $res = $self->client->post($self->api_url("lists"), [], $args);
    $self->decode_response($res);
}

sub list {
    my ($self, $address) = @_;

    my $res = $self->client->get($self->api_url(_path('lists', $address)));
    my $json = $self->decode_response($res) or return;
    return $json->{list};
}

sub update_list {
    my ($self, $address, $args) = @_;

    my $res = $self->client->put($self->api_url(_path('lists', $address)), [], $args);
    $self->decode_response($res);
}

sub delete_list {
    my ($self, $address) = @_;

    my $res = $self->client->delete($self->api_url(_path('lists', $address)));
    $self->decode_response($res);
}

sub list_members {
    my ($self, $address) = @_;

    return $self->recursive(_path('lists', $address, 'members', 'pages'));
}

sub add_list_member {
    my ($self, $address, $args) = @_;

    my $res = $self->client->post(
        $self->api_url(_path('lists', $address, 'members')), [], $args);
    $self->decode_response($res);
}

sub add_list_members {
    my ($self, $address, $args) = @_;

    my $res = $self->client->post(
        $self->api_url(_path('lists', $address, 'members.json')), [], $args);
    $self->decode_response($res);
}

sub list_member {
    my ($self, $address, $member) = @_;

    my $res = $self->client->get($self->api_url(_path('lists', $address, 'members', $member)));
    my $json = $self->decode_response($res) or return;
    return $json->{member};
}

sub update_list_member {
    my ($self, $address, $member, $args) = @_;

    my $res = $self->client->put(
        $self->api_url(_path('lists', $address, 'members', $member)), [], $args);
    $self->decode_response($res);
}

sub delete_list_member {
    my ($self, $address, $member) = @_;

    my $res = $self->client->delete(
        $self->api_url(_path('lists', $address, 'members', $member)));
    $self->decode_response($res);
}

sub event {
    my ($self, $query) = @_;

    my $api_url;
    if ((blessed($query) && $query->isa('URI')) || (defined $query && !ref $query)) {
        # A URL (the next URL an earlier call returned, for Event Polling) is fetched as it
        # is. Mailgun's paging URLs carry no credentials, so the API key is set on it: only for
        # an https URL on the API's own host, so that the key is never sent anywhere else.
        $api_url = blessed($query) ? $query->clone : URI->new($query);
        my ($host) = split m{/}, $self->api_base;
        unless (($api_url->scheme // '') eq 'https' && lc($api_url->host) eq lc($host)) {
            croak "event() takes a query hash reference or an https URL on $host, not '$query'";
        }
        $api_url->userinfo('api:'.$self->api_key);
    } else {
        $api_url = URI->new($self->domain_api_url("events"));
        $api_url->query_form($query);
    }
    return $self->recursive("events", {}, "items", $api_url);
}

sub get_message_from_event {
    my ($self, $event) = @_;

    die "invalid event! this method need 'stored' event only." if $event->{event} ne 'stored';
    my $uri = URI->new($event->{storage}->{url});
    $uri->userinfo('api:'.$self->api_key);

    my $res = $self->client->get($uri->as_string);
    $self->decode_response($res);
}

sub delete_templates {
    my ($self) = @_;

    my $res = $self->client->delete($self->domain_api_url("templates"));
    $self->decode_response($res);
}

sub delete_template {
    my ($self, $name) = @_;

    my $res = $self->client->delete(
        $self->domain_api_url(_path('templates', $name)));
    $self->decode_response($res);
}

sub add_template {
    my ($self, $args) = @_;

    my @content;
    if (ref($args) eq 'HASH') {
        @content = %$args;
    }
    elsif (ref($args) eq 'ARRAY') {
        @content = @$args;
    }
    else {
        die 'unsupport argument. add_template() need HashRef or ArrayRef.';
    }

    my $req = POST $self->domain_api_url('templates'), Content_type => 'form-data', Content => \@content;

    my $res = $self->client->request($req);
    $self->decode_response($res);
}

1;
__END__

=encoding utf-8

=head1 NAME

WebService::Mailgun - API client for Mailgun (L<https://mailgun.com/>)

=head1 SYNOPSIS

    use WebService::Mailgun;

    my $mailgun = WebService::Mailgun->new(
        api_key => '<YOUR_API_KEY>',
        domain => '<YOUR_MAIL_DOMAIN>',
    );

    # send mail
    my $res = $mailgun->message({
        from    => 'foo@example.com',
        to      => 'bar@example.com',
        subject => 'test',
        text    => 'text',
    }) or die $mailgun->error;

=head1 DESCRIPTION

WebService::Mailgun is a client for the Mailgun API (L<https://mailgun.com/>): sending messages
(also in MIME format), mailing lists and their members, events, stored messages and templates.

Each method sends one request, or a series of them for the methods that return every page of a
list, and returns the response decoded from JSON.

=head2 Errors

When a request fails, the method returns C<undef> (an empty list in list context), and
C<error> and C<error_status> tell why. With C<< RaiseError => 1 >>, it warns with the error
message and dies with the status line instead.

    my $res = $mailgun->message($args)
        or die sprintf '%s: %s', $mailgun->error_status, $mailgun->error;

A response that is not what Mailgun sends fails the same way, even with a C<2xx> status (then
in C<error_status>): a body that is not a JSON object, a page without its list of items, and a
C<paging.next> that points back to a page already fetched. An empty body (C<204 No Content>) is
a success with nothing in it.

The methods that return every page (L</Lists of every page>) do not return C<undef>: they stop
at the page that failed and return the items fetched so far. Without C<RaiseError>, a failure
there shows only in C<error>, which keeps the message of the last failure until the next one.

=head2 Lists of every page

C<lists>, C<list_members> and C<event> follow C<paging.next> until a page has no items, and
return two values: an array reference of all the items, and the C<paging.next> URL of that
empty page as a L<URI>, where the items that come later will be (for C<event>, see
L</Event Polling>). When a request fails, the second value is the URL of the page that failed
instead, so that the rest can be fetched from there. A page with no C<paging.next> is the last
one, and the second value is that page's own URL. Take the items in list context:

    my ($lists) = $mailgun->lists();
    my ($events, $next) = $mailgun->event({ event => 'stored', ascending => 'yes' });

In scalar context they return the URL, not the items.

=head1 METHODS

=head2 C<< new(api_key => $api_key, domain => $domain, region => "us"|"eu", RaiseError => 0|1) >>

Create a WebService::Mailgun object.

=head3 RaiseError (default: 0)

Die when a request fails, instead of returning C<undef> (see L</Errors>).

=head3 region (default: "us")

The region the domain belongs to: C<us> or C<eu>. Any other value dies when a request is made.

=head2 error

The error message of the last request that failed.

=head2 error_status

The status line (C<401 Unauthorized>, say) of the last request that failed (see L</Errors>).

=head2 message($args)

Send email message.

    # send mail
    my $res = $mailgun->message({
        from    => 'foo@example.com',
        to      => 'bar@example.com',
        subject => 'test',
        text    => 'text',
    });

To give a key several values, pass them in an array reference; the key is sent once for each:

    my $res = $mailgun->message({
        from    => 'foo@example.com',
        to      => ['bar@example.com', 'baz@example.com'],
        'o:tag' => ['newsletter', 'weekly'],
        subject => 'test',
        text    => 'text',
    });

An empty array reference dies, rather than leaving the key out.

C<attachment> and C<inline> are the exception: there an array reference is a file
(C<[$path]>, or C<[$path, $filename]>), as L<HTTP::Request::Common> takes it, and an array
reference of those is several files:

    attachment => [ ['/path/to/a.pdf'], ['/path/to/b.pdf', 'b.pdf'] ],

The same can be passed as an array reference of key-value pairs instead of a hash reference,
with the key given once for each file:

    my $res = $mailgun->message([
        from       => 'foo@example.com',
        to         => 'bar@example.com',
        subject    => 'test',
        text       => 'text',
        attachment => ['/path/to/a.pdf'],
        attachment => ['/path/to/b.pdf'],
    ]);

L<Send an email|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/messages/post-v3--domain-name--messages>

=head2 mime($args)

Send a MIME message you build yourself, usually by using a library to create that MIME message.
The C<to> parameter needs to be passed as one of the arguments.
Either the C<file> or C<message> parameter will also need to be passed.

The C<file> parameter should contain the path to the filename that holds the MIME message.
The C<message> parameter should contain either a string or a reference to a string that holds the MIME message:

    # send MIME message via a filename:
    my $res = $mailgun->mime({
        to   => 'bar@example.com',
        file => '/path/to/filename.mime',
    });

    # send MIME message via a string:
    use MIME::Entity;
    my $str = MIME::Entity->build(
        From    => 'foo@example.com',
        To      => 'bar@example.com',
        Subject => 'Subject',
        Data    => 'Message',
    )->as_string;

    my $res = $mailgun->mime({
        to      => 'bar@example.com',
        message => $str,
    });

    # or send MIME message via a string ref:
    my $res = $mailgun->mime({
        to      => 'bar@example.com',
        message => \$str,
    });

C<mime()> changes the hash reference it is given: C<message> becomes an array reference holding
the path of a temporary file (or of C<file>, which is removed). Pass a new hash reference for
each call.

L<Send a message in MIME format|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/messages/post-v3--domain-name--messages-mime>


=head2 lists()

Get list of mailing lists.

    # get mailing lists (every page; see "Lists of every page")
    my ($lists) = $mailgun->lists();
    # => ArrayRef of mailing list object.

L<Get mailing lists|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/get-v3-lists-pages>

=head2 add_list($args)

Add mailing list.

    # add mailing list
    my $res = $mailgun->add_list({
        address => 'ml@example.com', # Mailing list address
        name    => 'ml sample',      # Mailing list name (Optional)
        description => 'sample',     # description (Optional)
        access_level => 'members',   # readonly(default), members, everyone
    });

L<Create a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/post-v3-lists>

=head2 list($address)

Get detail for mailing list.

    # get mailing list detail
    my $data = $mailgun->list('ml@example.com');

L<Get a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/get-v3-lists-address>

=head2 update_list($address, $args)

Update mailing list detail.

    # update mailing list
    my $res = $mailgun->update_list('ml@example.com' => {
        address => 'ml@example.com', # Mailing list address (Optional)
        name    => 'ml sample',      # Mailing list name (Optional)
        description => 'sample',     # description (Optional)
        access_level => 'members',   # readonly(default), members, everyone
    });

L<Update a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/put-v3-lists-address>

=head2 delete_list($address)

Delete mailing list.

    # delete mailing list
    my $res = $mailgun->delete_list('ml@example.com');

L<Delete a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/delete-v3-lists-address>

=head2 list_members($address)

Get members for mailing list.

    # get members (every page; see "Lists of every page")
    my ($members) = $mailgun->list_members('ml@example.com');

L<Get members of a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/get-lists-list_address-members-pages>

=head2 add_list_member($address, $args)

Add member for mailing list.

    # add member
    my $res = $mailgun->add_list_member('ml@example.com' => {
        address => 'user@example.com', # member address
        name    => 'username',         # member name (Optional)
        vars    => '{"age": 34}',      # member params(JSON string) (Optional)
        subscribed => 'yes',           # yes(default) or no
        upsert     => 'no',            # no (default). if yes, update exists member
    });

L<Add a member to a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/post-lists-string:list_address-members>

=head2 add_list_members($address, $args)

Adds multiple members for mailing list.

    use JSON; # auto export 'encode_json'

    # add members
    my $res = $mailgun->add_list_members('ml@example.com' => {
        members => encode_json [
            { address => 'user1@example.com' },
            { address => 'user2@example.com' },
            { address => 'user3@example.com' },
        ],
        upsert  => 'no',            # no (default). if yes, update exists member
    });

    # or just the addresses
    my $res = $mailgun->add_list_members('ml@example.com' => {
        members => encode_json [qw/user1@example.com user2@example.com/],
    });

L<Add members to a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/post-lists-list_address-members.json>

=head2 list_member($address, $member_address)

Get member detail.

    # get member
    my $member = $mailgun->list_member('ml@example.com', 'user@example.com');

L<Get a member of a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/get-lists-list_address-members-member_address>

=head2 update_list_member($address, $member_address, $args)

Update member detail.

    # update member
    my $res = $mailgun->update_list_member('ml@example.com', 'user@example.com' => {
        address => 'user@example.com', # member address (Optional)
        name    => 'username',         # member name (Optional)
        vars    => '{"age": 34}',      # member params(JSON string) (Optional)
        subscribed => 'yes',           # yes(default) or no
    });

L<Update a member of a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/put-lists-list_address-members-member_address>

=head2 delete_list_member($address, $member_address)

Delete member for mailing list.

    # delete member
    my $res = $mailgun->delete_list_member('ml@example.com' => 'user@example.com');

L<Delete a member of a mailing list|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/mailing-lists/delete-lists-list_address-members-member_address>

=head2 event($args|$url)

Get event data. C<$args> is a hash reference of the query. In its place C<$url> (a L<URI> or a
string) is fetched as it is, such as the second value an earlier call returned (see
L</Event Polling>); it must be an https URL on the API's host, or C<event> dies.

    # get event data (every page; see "Lists of every page")
    my ($events, $next) = $mailgun->event({ event => 'stored', limit => 50 });

L<Get events|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/events/get-v3-domain_name-events>

=head2 get_message_from_event($event)

Get stored message. C<$event> must be a C<stored> event; any other event dies.

    # get event data
    my ($events) = $mailgun->event({ event => 'stored' });
    my $msg = $mailgun->get_message_from_event($events->[0]);

L<Retrieve a stored email|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/messages/get-v3-domains--domain-name--messages--storage-key->

=head2 add_template($args)

Add a template. Like C<message>, it takes a hash reference or an array reference of key-value
pairs. Unlike C<message>, an array reference as a value is always a file (C<[$path]>), as
L<HTTP::Request::Common> takes it, such as the template read from a file.

    # add template
    my $res = $mailgun->add_template({
        name        => 'welcome',     # Template name
        template    => 'Hello!',      # Template data
        engine      => 'handlebars',  # Template engine (optional)
        description => 'xyz',         # Description of template (optional)
        tag         => '2.0' ,        # Version tag (optional)
        comment     => 'Test',        # Version comment (optional)
    });

L<Create a template|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/domain-templates/post-v3--domain-name--templates>

=head2 delete_templates()

Delete all templates of the domain.

    my $res = $mailgun->delete_templates();

L<Delete all templates|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/domain-templates/delete-v3--domain-name--templates>

=head2 delete_template($name)

Delete a template.

    my $res = $mailgun->delete_template($name);

L<Delete a template|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/domain-templates/delete-v3--domain-name--templates--template-name->

=head1 Event Polling

The second value C<event> returns is the C<paging.next> URL of the empty page it stopped at, as a
L<URI> with the API key set. Pass it back to C<event> in place of the query, and it returns the
events stored since the last call, and the URL to use the next time:

    use Time::Piece;

    my ($events, $next) = $mailgun->event({
        event     => 'stored',
        begin     => localtime->epoch - 30 * 60,
        ascending => 'yes',
    });
    while (1) {
        # do something with @$events ...
        sleep 60;
        ($events, $next) = $mailgun->event($next);
    }

Use C<< ascending => 'yes' >>, so that the URL points forward in time.

Mailgun may store an event some time after it happens. Such an event can be dated before events
already fetched, and the URL does not return it. If every event matters, fetch a time range
again once it is old enough (Mailgun's documentation suggests half an hour), and drop the events
whose C<id> was seen already.

L<Event Polling|https://documentation.mailgun.com/docs/mailgun/user-manual/events/event-polling>


=head1 TODO

These APIs are not implemented yet.

=over

=item * L<Domains|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/domains>

=item * L<Stats|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/stats>

=item * L<Tags|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/tags>

=item * Suppressions (L<Bounces|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/bounces>, L<Unsubscribes|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/unsubscribe>, L<Complaints|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/complaints>, L<Allowlist|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/allowlist>)

=item * L<Routes|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/routes>

=item * L<Webhooks|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/webhooks>

=item * L<Email Validation|https://documentation.mailgun.com/docs/mailgun/api-reference/send/validate/validations>

=item * L<Templates|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/domain-templates> (only creating and deleting are implemented)

=back

=head1 SEE ALSO

=over

=item * L<Mailgun API reference|https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/messages>

=item * L<WWW::Mailgun>, another client for the Mailgun API

=back

=head1 LICENSE

Copyright (C) Kan Fushihara.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kan Fushihara E<lt>kan.fushihara@gmail.comE<gt>

=cut

