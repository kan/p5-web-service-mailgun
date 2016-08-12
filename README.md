# NAME

WebService::Mailgun - API client for Mailgun ([https://mailgun.com/](https://mailgun.com/))

# SYNOPSIS

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
    });

# DESCRIPTION

WebService::Mailgun is API client for Mailgun ([https://mailgun.com/](https://mailgun.com/)).

# METHOD

## new(api\_key => $api\_key, domain => $domain)

Create mailgun object.

## message($args)

Send email message.

    # send mail
    my $res = $mailgun->message({
        from    => 'foo@example.com',
        to      => 'bar@example.com',
        subject => 'test',
        text    => 'text',
    });

[https://documentation.mailgun.com/api-sending.html#sending](https://documentation.mailgun.com/api-sending.html#sending)

## lists()

Get list of mailing lists.

    # get mailing lists
    my $lists = $mailgun->lists();
    # => ArrayRef of mailing list object.

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## add\_list($args)

Add mailing list.

    # add mailing list
    my $res = $mailgun->add_list({
        address => 'ml@example.com', # Mailing list address
        name    => 'ml sample',      # Mailing list name (Optional)
        description => 'sample',     # description (Optional)
        access_level => 'members',   # readonly(default), members, everyone
    });

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## list($address)

Get detail for mailing list.

    # get mailing list detail
    my $data = $mailgun->list('ml@exmaple.com');

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## update\_list($address, $args)

Update mailing list detail.

    # update mailing list
    my $res = $mailgun->update_list('ml@example.com' => {
        address => 'ml@example.com', # Mailing list address (Optional)
        name    => 'ml sample',      # Mailing list name (Optional)
        description => 'sample',     # description (Optional)
        access_level => 'members',   # readonly(default), members, everyone
    });

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## delete\_list($address)

Delete mailing list.

    # delete mailing list
    my $res = $mailgun->delete_list('ml@example.com');

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## list\_members($address)

Get members for mailing list.

    # get members
    my $res = $mailgun->list_members('ml@example.com');

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## add\_list\_member($address, $args)

Add member for mailing list.

    # add member
    my $res = $mailgun->add_list_member('ml@example.com' => {
        address => 'user@example.com', # member address
        name    => 'username',         # member name (Optional)
        vars    => '{"age": 34}',      # member params(JSON string) (Optional)
        subscribed => 'yes',           # yes(default) or no
        upsert     => 'no',            # no (default). if yes, update exists member
    });

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## add\_list\_members($address, $args)

Adds multiple members for mailing list.

    use JSON::XS; # auto export 'encode_json'

    # add members
    my $res = $mailgun->add_list_members('ml@example.com' => {
        members => encode_json [
            { address => 'user1@example.com' },
            { address => 'user2@example.com' },
            { address => 'user3@example.com' },
        ],
        upsert  => 'no',            # no (default). if yes, update exists member
    });

    # too simple
    my $res = $mailgun->add_list_members('ml@example.com' => {
        members => encode_json [qw/user1@example.com user2@example.com/],
    });

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## list\_member($address, $member\_address)

Get member detail.

    # update member
    my $res = $mailgun->list_member('ml@example.com', 'user@example.com');

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## update\_list\_member($address, $member\_address, $args)

Update member detail.

    # update member
    my $res = $mailgun->update_list_member('ml@example.com', 'user@example.com' => {
        address => 'user@example.com', # member address (Optional)
        name    => 'username',         # member name (Optional)
        vars    => '{"age": 34}',      # member params(JSON string) (Optional)
        subscribed => 'yes',           # yes(default) or no
    });

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

## delete\_list\_members($address, $member\_address)

Delete member for mailing list.

    # delete member
    my $res = $mailgun->delete_list_member('ml@example.com' => 'user@example.com');

[https://documentation.mailgun.com/api-mailinglists.html#mailing-lists](https://documentation.mailgun.com/api-mailinglists.html#mailing-lists)

# TODO

this API not implement yet.

- [Domains](https://documentation.mailgun.com/api-domains.html)
- [Events](https://documentation.mailgun.com/api-events.html)
- [Stats](https://documentation.mailgun.com/api-stats.html)
- [Tags](https://documentation.mailgun.com/api-tags.html)
- [Suppressions](https://documentation.mailgun.com/api-suppressions.html)
- [Routes](https://documentation.mailgun.com/api-routes.html)
- [Webhooks](https://documentation.mailgun.com/api-webhooks.html)
- [Email Validation](https://documentation.mailgun.com/api-email-validation.html)

# SEE ALSO

[WWW::Mailgun](https://metacpan.org/pod/WWW::Mailgun), [https://documentation.mailgun.com/](https://documentation.mailgun.com/)

# LICENSE

Copyright (C) Kan Fushihara.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Kan Fushihara <kan.fushihara@gmail.com>
