requires 'Class::Accessor::Lite';
requires 'IO::Socket::SSL';
requires 'Furl';
requires 'JSON::XS';
requires 'URI';
requires 'perl', '5.008001';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::Exception';
    requires 'String::Random';
};

on 'develop' => sub {
    requires 'Pod::Markdown::Github';
};
