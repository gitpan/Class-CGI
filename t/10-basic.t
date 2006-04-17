#!perl

use Test::More tests => 35;
#use Test::More qw/no_plan/;
use Test::Exception;
use lib 't/lib';

use Class::CGI handlers => {
    customer => 'Class::CGI::Customer',
    sales    => 'Class::CGI::SyntaxError',
};

my $CGI = 'Class::CGI';
can_ok $CGI, 'new';

my $params = { customer => 2, email => 'some@example.com' };

# test that basic functionality works

ok my $cgi = $CGI->new($params), '... and calling it should succeed';
isa_ok $cgi, $CGI, '... and the object it returns';

can_ok $cgi, 'handlers';
ok my $handlers = $cgi->handlers, '... and calling it should succeed';
is_deeply $handlers,
  { customer => 'Class::CGI::Customer', sales => 'Class::CGI::SyntaxError' },
  '... and it should return a hashref of the current handlers';

can_ok $cgi, 'param';
ok my $customer = $cgi->param('customer'),
  '... and calling it should succeed';
isa_ok $customer, 'Example::Customer', '... and the object it returns';
is $customer->id,    2,         '... with the correct ID';
is $customer->first, 'Corinna', '... and the correct first';

ok my $email = $cgi->param('email'),
  'Calling params for which we have no handler should succeed';
is $email, 'some@example.com',
  '... and simply return the raw value of the parameter';

my @params = sort $cgi->param;
is_deeply \@params, [qw/customer email/],
  'Calling param() without arguments should succeed';

# test multiple values for unhandled params

$params = { sports => [qw/ basketball soccer Scotch /] };
$cgi = $CGI->new($params);
my $sport = $cgi->param('sports');
is $sport, 'basketball',
  'Calling a multi-valued param in scalar context should return the first value';
my @sports = $cgi->param('sports');
is_deeply \@sports, [qw/ basketball soccer Scotch /],
  '... and calling it in list context should return all values';

# test bad handlers

throws_ok { $cgi->param('sales') }
  qr{^\QCould not load 'Class::CGI::SyntaxError': syntax error at},
  'Trying to fetch a param with a bad handler should fail';

# test some import errors

throws_ok { Class::CGI->import('handlers') } qr/No handlers defined/,
  'Failing to provide handlers should throw an exception';

throws_ok { Class::CGI->import( handlers => [qw/Class::CGI::Customer/] ) }
  qr/No handlers defined/,
  'Failing to provide a hashref of handlers should throw an exception';

# Note that some of the following tests are not quite necessary as the
# exception handling is up to those who implement handlers.  However, I
# include them here so folks can see how this works.

# test that we cannot use invalid ids

$params = { customer => 'Ovid' };
$cgi = $CGI->new($params);
ok !$cgi->param('customer'),
  'Trying to fetch a value with an invalid ID should fail';

can_ok $cgi, 'errors';
ok my @errors = $cgi->errors, '... and it should return the generated errors';
is scalar @errors, 1, '... and they should be the correct number of errors';
like $errors[0], qr/^\QInvalid id (Ovid) for Class::CGI::Customer/,
  '... and be the errors thrown by the handlers';

# test that we cannot use a non-existent id

$params = { customer => 3 };
$cgi = $CGI->new($params);
ok !$cgi->param('customer'),
  'Trying to fetch a value with a non-existent ID should fail';

ok my $errors = $cgi->errors, '... and we should have the errors available';
is scalar @$errors, 1, '... and they should be the correct number of errors';
like $errors->[0], qr/^\QCould not find customer for (3)/,
  '... and the new error should be correct';

ok !$cgi->param('customer'),
  'Trying to refetch a value with a non-existent ID should fail';

ok $errors = $cgi->errors, '... and we should have the errors available';
is scalar @$errors, 2, '... and they should be the correct number of errors';
like $errors->[1], qr/^\QCould not find customer for (3)/,
  '... and the new error should be correct';

can_ok $cgi, 'clear_errors';
ok $cgi->clear_errors, '... and clearing the errors should be successful';
ok !( @errors = $cgi->errors ),
  '... and we should have no more errors reported';
