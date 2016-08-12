requires 'Class::Accessor::Lite';
requires 'IO::Socket::SSL';
requires 'Furl';
requires 'JSON::XS';
requires 'perl', '5.008001';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

