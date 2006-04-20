package Class::CGI;

use warnings;
use strict;

use CGI::Simple 0.077;
use Module::Load::Conditional qw/check_install/;
use base 'CGI::Simple';

=head1 NAME

Class::CGI - Fetch objects from your CGI object

=head1 VERSION

Version 0.11

=cut

our $VERSION = '0.11';

=head1 SYNOPSIS

    use Class::CGI
        handlers => {
            customer_id => 'Class::CGI::Customer'
        };

    my $cgi      = Class::CGI->new;
    my $customer = $cgi->param('customer_id');
    my $name     = $customer->name;
    my $email    = $cgi->param('email'); # behaves like normal

    if ( my @errors = $cgi->errors ) {
       # do error handling
    }

=head1 DESCRIPTION

For small CGI scripts, it's common to get a parameter, untaint it, pass it to
an object constructor and get the object back. This module would allow one to
to build C<Class::CGI> handler classes which take the parameter value,
automatically perform those steps and just return the object. Much grunt work
goes away and you can get back to merely I<pretending> to work.

Because this module is a subclass of C<CGI::Simple>, all of C<CGI::Simple>'s
methods and behaviors should be available.  We do not subclass off of C<CGI>
because C<CGI::Simple> is faster and it's assumed that if we're going the full
OO route that we are already using templates.  Thus, the C<CGI> HTML
generation methods are not available.  This decision may be revisited in the
future.

=head1 EXPORT

None.

=head1 BASIC USE

The simplest method of using C<Class::CGI> is to simply specify each form
parameter's handler class in the import list:

  use Class::CGI
    handlers => {
      customer => 'Class::CGI::Customer',
      sales    => 'Sales::Loader'
    };

  my $cgi = Class::CGI->new;
  my $customer = $cgi->param('customer');
  my $email    = $cgi->param('email');
  # validate email
  $customer->email($email);
  $customer->save;

Note that there is no naming requirement for the handler classes and any form
parameter which does not have a handler class behaves just like a normal form
parameter.  Each handler class is expected to have a constructor named C<new>
which takes the B<raw> form value and returns an object corresponding to that
value.  All untainting and validation is expected to be dealt with by the
handler.  See L<WRITING HANDLERS>.

If you need different handlers for the same form parameter names (this is
common in persistent environments) you may omit the import list and use the
C<handlers> method.

=head1 LOADING THE HANDLERS

When the handlers are specified, either via the import list or the
C<handlers()> method, we verify that the handler exists and C<croak()> if it
is not.  However, we do not load the handler until the parameter for that
handler is fetched.  This allows us to not load unused handlers but still have
a semblance of safety that the handlers actually exist.

=head1 METHODS

=cut

my %class_for;

sub import {
    my $class = shift;

    my ( $config, $use_profiles );
    @_ = @_;    # this avoids the "modification of read-only value" error when
                # we assign undef the elements
    foreach my $i ( 0 .. $#_ ) {

        # we sometimes hit unitialized values due to "undef"ing array elements
        no warnings 'uninitialized';
        my ( $arg, $value ) = @_[ $i, $i + 1 ];
        if ( 'handlers' eq $arg ) {
            if ( !ref $value || 'HASH' ne ref $value ) {
                $class->_croak("No handlers defined");
            }
            while ( my ( $profile, $handler ) = each %$value ) {
                $class_for{$profile} = $handler;
            }
            @_[ $i, $i + 1 ] = ( undef, undef );
            next;
        }
        if ( 'use' eq $arg ) {
            $value = [$value] unless 'ARRAY' eq ref $value;
            $use_profiles = $value;
            @_[ $i, $i + 1 ] = ( undef, undef );
            next;
        }
        if ( 'profiles' eq $arg ) {
            if ( -f $value ) {
                require Config::Std;
                Config::Std->import;
                read_config( $value => \$config );
            }
            else {

                # eventually we may want to allow them to specify a config
                # class instead of a file.
                $class->_croak("Can't find profile file '$value'");
            }
            @_[ $i, $i + 1 ] = ( undef, undef );
        }
    }
    if ($config) {
        unless ($use_profiles) {
            while ( my ( $profile, $handler )
                = each %{ $config->{profiles} } )
            {

                # the "unless" is here because users may override profile
                # parameter specifications in their code, if they prefer
                $class_for{$profile} = $handler
                  unless exists $class_for{$profile};
            }
        }
        else {
            foreach my $profile (@$use_profiles) {
                my $handler = $config->{profiles}{$profile}
                  or
                  $class->_croak("No handler found for parameter '$profile'");
                $class_for{$profile} = $handler;
            }
        }
    }

    @_ = grep {defined} @_;
    $class->_verify_installed( values %class_for );
    goto &CGI::Simple::import;    # don't update the call stack
}

# testing hook
sub _clear_global_handlers {
    %class_for = ();
}

sub _verify_installed {
    my ( $proto, @modules ) = @_;
    my @not_installed_modules;
    foreach my $module (@modules) {
        check_install( module => $module )
          or push @not_installed_modules => $module;
    }
    if (@not_installed_modules) {
        $proto->_croak(
            "The following modules are not installed: (@not_installed_modules)"
        );
    }
    return $proto;
}

##############################################################################

=head2 handlers

  use Class::CGI;
  my $cust_cgi = Class::CGI->new;
  $cust_cgi->handlers(
    customer => 'Class::CGI::Customer',
  );
  my $order_cgi = Class::CGI->new($other_params);
  $order_cgi->handlers(
    order    => 'Class::CGI::Order',
  );
  my $customer = $cust_cgi->param('customer');
  my $order    = $order_cgi->param('order');
  $order->customer($customer);

  my $handlers = $cgi->handlers; # returns hashref of current handlers
 
Sometimes we get our CGI parameters from different sources.  This commonly
happens in a persistent environment where the class handlers for one form may
not be appropriate for another form.  When this occurs, you may set the
handler classes on an instance of the C<Class::CGI> object.  This overrides
global class handlers set in the import list:

  use Class::CGI handlers => { customer => "Some::Customer::Handler" };
  my $cgi = Class::CGI->new;
  $cgi->handlers( customer => "Some::Other::Customer::Handler" );

In the above example, the C<$cgi> object will not use the
C<Some::Customer::Handler> class.

If called without arguments, returns a hashref of the current handlers in
effect.

=cut

sub handlers {
    my $self = shift;
    if ( my %handlers = @_ ) {
        $self->{class_cgi_handlers} = \%handlers;
        $self->_verify_installed( values %handlers );
        return $self;
    }

    # else called without arguments
    if ( my $handlers = $self->{class_cgi_handlers} ) {
        return $handlers;
    }
    return \%class_for;
}

##############################################################################

=head2 profiles

  $cgi->profiles($profile_file, @use);

If you prefer, you can specify a config file listing the available
C<Class::CGI> profile handlers and an optional list stating which of the
profiles to use.  If the C<@use> list is not specified, all profiles will be
used.  Otherwise, only those profiles listed in C<@use> will be used.  These
profiles are used on a per instance basis, similar to C<&handlers>.

See L<DEFINING PROFILES> for more information about the profile configuration
file.

=cut

sub profiles {
    my ( $self, $profiles, @use ) = @_;
    unless ( -f $profiles ) {

        # eventually we may want to allow them to specify a config
        # class instead of a file.
        $self->_croak("Can't find profile file '$profiles'");
    }

    require Config::Std;
    Config::Std->import;
    read_config( $profiles => \my %config );
    my %handler_for = %{ $config{profiles} };
    if (@use) {
        my %used;
        foreach my $profile (@use) {
            if ( exists $handler_for{$profile} ) {
                $used{$profile} = 1;
            }
            else {
                $self->_croak("No handler found for parameter '$profile'");
            }
        }
        foreach my $profile ( keys %handler_for ) {
            delete $handler_for{$profile} unless $used{$profile};
        }
    }
    $self->handlers(%handler_for);
}

##############################################################################

=head2 param

 use Class::CGI
     handlers => {
         customer => 'Class::CGI::Customer'
     };

 my $cgi = Class::CGI->new;
 my $customer = $cgi->param('customer'); # returns an object, if found
 my $email    = $cgi->param('email');    # returns the raw value
 my @sports   = $cgi->param('sports');   # behaves like you would expect

If a handler is defined for a particular parameter, the C<param()> calls the
C<new()> method for that handler, passing the C<Class::CGI> object and the
parameter's value.  Returns the value returned by C<new()>.  In the example
above, for "customer", the return value is essentially:

 return Class::CGI::Customer->new( $self );

=cut

sub param {
    my $handler_for = $_[0]->{class_cgi_handlers} || \%class_for;
    if ( 2 != @_ || ( 2 == @_ && !exists $handler_for->{ $_[1] } ) ) {

        # this allows multi-valued params for parameters which do not have
        # helper classes and also allows for my @params = $cgi->param;
        goto &CGI::Simple::param;
    }
    my ( $self, $param ) = @_;
    my $class = $handler_for->{$param};
    eval "require $class";
    $self->_croak("Could not load '$class': $@") if $@;
    my $result;
    eval { $result = $class->new( $self, $param ) };
    if ( my $error = $@ ) {
        $self->_add_error($param, $error);
        return;
    }
    return $result;
}

##############################################################################

=head2 raw_param

  my $id = $cgi->raw_param('customer');

This method returns the actual value of a parameter, ignoring any handlers
defined for it.

=cut

sub raw_param {
    my $self = shift;
    return $self->SUPER::param(@_);
}

##############################################################################

=head2 errors

  if ( my @errors = $cgi->errors ) {
      ...
  }

Returns exceptions thrown by handlers, if any.  In scalar context, returns an
array reference.  Note that these exceptions are generated via the overloaded
C<&param> method.  For example, let's consider the following:

    use Class::CGI
        handlers => {
            customer => 'Class::CGI::Customer',
            date     => 'Class::CGI::Date',
            order    => 'Class::CGI::Order',
        };

    my $cgi      = Class::CGI->new;
    my $customer = $cgi->param('customer');
    my $date     = $cgi->param('date');
    my $order    = $cgi->param('order');

    if ( my %errors = $cgi->errors ) {
       # do error handling
    }

If errors are generated by the param statements, returns a hash of the errors.
The keys are the param names and the values are whatever exception the handler
throws.  Returns a hashref in scalar context.

If any of the C<< $cgi->param >> calls generates an error, it will B<not> throw
an exception.  Instead, control will pass to the next statement.  After all
C<< $cgi->param >> calls are made, you can check the C<&errors> method to see
if any errors were generated and, if so, handle them appropriately.

This allows the programmer to validate the entire set of form data and report
all errors at once.  Otherwise, you wind up with the problem often seen on Web
forms where a customer will incorrectly fill out multiple fields and have the
Web page returned for the first error, which gets corrected, and then the page
returns the next error, and so on.  This is very frustrating for a customer
and should be avoided at all costs.

=cut

sub errors {
    my $self = shift;
    return wantarray
      ? %{ $self->{class_cgi_errors} || {} }
      : $self->{class_cgi_errors};
}

##############################################################################

=head2 clear_errors 

  $cgi->clear_errors;

Deletes all errors returned by the C<&errors> method.

=cut

sub clear_errors {
    my $self = shift;
    $self->{class_cgi_errors} = {};
    return $self;
}

sub _add_error {
    my ($self, $param, $error) = @_;
    $self->{class_cgi_errors}{$param} = $error;
    return $self;
}

sub _croak {
    my ( $proto, $message ) = @_;
    require Carp;
    Carp::croak $message;
}

=head1 WRITING HANDLERS

=head2 A basic handler

Here's a complete, accurate, one-sentence desription of a handler:  a handler
is a class whose constructor, C<new()>, takes the C<Class::CGI> object and the
requested parameter name and returns an appropriate object.  You've now
learned pretty much everything you need to know about writing handlers.

Writing a handler is a fairly straightforward affair.  Let's assume that our
form has a parameter named "customer" and this parameter should point to a
customer ID.  The ID is assumed to be a positive integer value.  For this
example, we assume that our customer class is named C<My::Customer> and we
load a customer object with the C<load_from_id()> method.  The handler might
look like this:

  package Class::CGI::Customer;
  
  use strict;
  use warnings;
  use My::Customer;
  
  sub new {
      my ($class, $cgi, $param) = @_;
      my $id = $cgi->raw_param($param);
      
      unless ( $id && $id =~ /^\d+$/ ) {
          die "Invalid id ($id) for $class";
      }
      return My::Customer->load_from_id($id)
          || die "Could not find customer for ($id)";
  }
  
  1;

Pretty simple, eh?

Using this in your code is as simple as:

  use Class::CGI
    handlers => {
      customer => 'Class::CGI::Customer',
    };

If C<Class::CGI> is being used in a persistent environment and other forms
might have a param named C<customer> but this param should not become a
C<My::Customer> object, then set the handler on the instance instead:

  use Class::CGI;
  my $cgi = Class::CGI->new;
  $cgi->handlers( customer => 'Class::CGI::Customer' );

=head2 A more complex example

Of course, while instantiating existing instances is useful, you will probably
often find yourself in the position whereby you want to handle multiple fields
with the same handler.  This is also trivial.  With the above example, let's
say that we want to instantiate the customer if we have a customer param.
Otherwise, we instantiate the customer from the parameters "first" and "last".

  package Class::CGI::Customer;
  
  use strict;
  use warnings;
  use Customer;
  
  sub new {
      my ( $class, $cgi ) = @_;
      my $value = $cgi->raw_param('customer');
  
      if ( defined $value ) {
          unless ( $value && $value =~ /^\d+$/ ) {
              die "Invalid id ($value) for $class";
          }
          return Customer->new($value)
            || die "Could not find customer for ($value)";
      }
      else {
          my $first = $cgi->raw_param('first');
          my $last  = $cgi->raw_param('last');
  
          # pretend we validated and untainted here :)
          return Customer->new->first($first)->last($last);
      }
  }
  
  1;


Again, it's pretty simple to do.  The handler bears full responsibility for
ensuring it has the data it needs.

As a more common example, let's say you have the following data in a form:

  <select name="month">
    <option value="01">January</option>
    ...
    <option value="12">December</option>
  </select>
  <select name="day">
    <option value="01">1</option>
    ...
    <option value="31">31</option>
  </select>
  <select name="year">
    <option value="2006">2006</option>
    ...
    <option value="1900">1900</option>
  </select>

Ordinarily, pulling all of that out, untainting it is a pain.  Here's a
hypothetical handler for it:

  package My::Date::Handler;

  use My::Date;

  sub new {
      my ($class, $cgi) = @_;
      my $month = $cgi->raw_param('month');
      my $day   = $cgi->raw_param('day');
      my $year  = $cgi->raw_param('year');
      return My::Date->new(
        month => $month,
        day   => $day,
        year  => $year,
      );
  }

  1;

And in the user's code:

  use Class::CGI
    handlers => {
      date => 'My::Date::Handler',
    };

  my $cgi  = Class::CGI->new;
  my $date = $cgi->param('date');
  my $day  = $date->day;

Note that this does not even require an actual param named "date" in the form.
The handler encapsulates all of that and the end user does not need to know
the difference.

=head2 Reusing handlers

Sometimes you might want to use a handler more than once for the same set of
data.  For example, you might want to have more than one date on a page.  To
handle issues like this, we pass in the parameter name to the constructor so
you can know I<which> date you're trying to fetch.

So for example, let's say their are three dates in a form.  One is the
customer birth date, one is an order date and one is just a plain date.  Maybe
our code will look like this:

 $cgi->handlers(
     birth_date => 'Class::CGI::Date',
     order_date => 'Class::CGI::Date',
     date       => 'Class::CGI::Date',
 );

One way of handling that would be the following:

 package Class::CGI::Date;
 
 use strict;
 use warnings;
 
 use My::Date;
 
 sub new {
     my ( $self, $cgi, $param ) = @_;
     my $prefix;
     if ( 'date' eq $param ) {
         $prefix = '';
     }
     else {
         ($prefix = $param) =~ s/date$//;
     }
     my ( $day,  $month, $year )  =
       grep {defined}
       map  { $cgi->param("$prefix$_") } qw/day month year/;

     return My::Date->new(
         day   => $day,
         month => $month,
         year  => $year,
     );
 }
 
 1;

For that, the birthdate will be built from params named C<birth_day>,
C<birth_month> and C<birth_year>.  The order date would be C<order_day> and so
on.  The "plain" date would be built from params named C<day>, C<month>, and
C<year>.  Thus, all three could be accessed as follows:

 my $birthdate  = $cgi->param('birth_date');
 my $order_date = $cgi->param('order_date');
 my $date       = $cgi->param('date');

=head1 DEFINING PROFILES

Handlers for parameters may be defined in an import list:

  use Class::CGI
      handlers => {
          customer   => 'Class::CGI::Customer',
          order_date => 'Class::CGI::Date',
          order      => 'Class::CGI::Order',
      };

=head2 Creating a profile file

For larger sites, it's not very practical to replicate this in all code which
needs it.  Instead, C<Class::CGI> allows you to define a "profiles" file.
This is a configuration file which should match the C<Congif::Std> format.  At
the present time, only one section, "profiles", is supported.  This should be
followed by a set of colon-delimited key/value pairs specifying the CGI
parameter name and the handler class for the parameter.  The above import list
could be listed like this in the file:

  [profiles]
  customer:   Class::CGI::Customer
  order_date: Class::CGI::Date
  order:      Class::CGI::Order

You may then use the profiles in your code as follows:

  use Class::CGI profiles => $location_of_profile_file;

It may be the case that you don't want all of the profiles.  In that case, you
can list a "use" section for that:

  use Class::CGI 
    profiles => $location_of_profile_file,
    use      => [qw/ order_date order /];
    
As with C<&handlers>, you may find that you don't want the profiles globally
applied.  In that case, use the C<&profiles> method described above:

  $cgi->profiles( $profile_file, @optional_list_of_profiles_to_use );

=head1 TODO

This module should be considered alpha code.  It probably has bugs.  Comments
and suggestions welcome.

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-class-cgi@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-CGI>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SEE ALSO

This module is based on the philosophy of building super-simple code which
solves common problems with a minimum of memorization.  That being said, it
may not be the best fit for your code.  Here are a few other options to
consider.

=over 4

=item * 
Data::FormValidator - Validates user input based on input profile

=item *
HTML::Widget - HTML Widget And Validation Framework 

=item *
Rose::HTML::Objects - Object-oriented interfaces for HTML

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Aristotle for pointing out how useful passing the parameter name to
the handler would be.

=head1 COPYRIGHT & LICENSE

Copyright 2006 Curtis "Ovid" Poe, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
