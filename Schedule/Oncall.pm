# $Id: Oncall.pm 1.14 Thu, 18 Jul 2002 10:34:53 -0400 trockij $
#
# Copyright 2001-2002 Jim Trocki
# Copyright 2001-2002 Transmeta Corporation
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#
package Schedule::Oncall;
require Exporter;
require 5.004;

use strict;

use POSIX qw (strftime);
use Sys::Hostname;
use Date::Manip;

my @ISA = qw(Exporter);
my $VERSION = "0.0101";


sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self  =
    {
	"date"		=> time,
	"people"	=> {},
	"sched"		=> [],
	"oncall-now"	=> { "username" => "nobody" },
	"vars"		=> {},
	"text"		=> {},
	"text-defaults"	=> {},
	"earliest"	=> 1440,
	"latest"	=> 0,
	"span"		=> 1440,
	"warn"		=> 1,
	"loaded_files"	=> [],
	"erro"		=> "",
    };

    bless ($self, $class);
    return $self;
}


sub schedule
{
    my $self = shift;
    my $person = shift;

    $self->{"error"} = "";

    return (@{$self->{"sched"}});
}


sub error
{
    my $self = shift;

    $self->{"error"};
}


sub info
{
    my $self = shift;
    my $person = shift;

    $self->{"error"} = "";

    if (!defined $self->{"people"}->{$person})
    {
    	$self->{"error"} = "person does not exist";
	return undef;
    }

    return ( %{$self->{"people"}->{$person}} );
}


#
# return who is on call for a particular date
# and set vars in $sched->{"oncall-now"} for that user
#
# returns the username of who is on call, or
# undef if not found for any reason
#
sub oncall
{
    my $self = shift;
    my $time = shift;

    $self->{"error"} = "";

    if (@{$self->{"sched"}} == 0)
    {
    	$self->{"error"} = "no schedule loaded";
	return undef;
    }

    if (!defined $time)
    {
    	$time = time;
    }

    my @t = localtime ($time);

    #
    # sunday = 0
    #
    my $wday = $t[6];

    if (!defined $self->{"sched"}->[$wday])
    {
    	$self->{"error"} = "day not defined";
	return undef;
    }

    #
    # $time_mins is the time relative to the beginning of the day
    #
    my $time_mins = $t[2] * 60 + $t[1];

    my $found = -1;
    my $entry;

    for (my $i = 0; $i < @{$self->{"sched"}->[$wday]}; $i++)
    {
	$entry = $self->{"sched"}->[$wday]->[$i];

    	if ($time_mins >= $entry->[0] && $time_mins <= $entry->[1])
	{
	    $found = $i;
	    last;
	}
    }

    if ($found == -1)
    {
    	$self->{"error"} = "schedule does not include time";
	return undef;
    }

    $self->{"oncall-now"} = {
    	"username" => "nobody",
    };

    if ($entry->[2] ne "")
    {
    	$self->{"oncall-now"}->{"username"} = $entry->[2];
    }

    foreach my $key (keys %{$self->{"people"}->{$entry->[2]}})
    {
    	$self->{"oncall-now"}->{$key} = join (",", @{$self->{"people"}->{$entry->[2]}->{$key}});
    }

    return $entry->[2];
}



#
# read in schedule
#
# arguments:
#
#  "date"	=> time,
#  "week"	=> num,
#  "month"	=> num,
#  "dir"	=> "path",
#  "file"	=> "file",
#
# returns undef on error
#
sub load
{
    my $self = shift;

    my (%args) = @_;

    $self->{"error"} = "";

    if (!$args{"date"})
    {
	$args{"date"} = time;
    }

    my $DIR = ".";
    my $SCHED_FILE = "schedule";
    my $FILE;

    if ($args{"dir"})
    {
    	$DIR = $args{"dir"};
    }

    if ($args{"file"})
    {
    	$SCHED_FILE = $args{"file"};
    }

    if ($SCHED_FILE =~ /^\//)
    {
    	$FILE = $SCHED_FILE;
    }

    else
    {
    	$FILE = "$DIR/$SCHED_FILE";
    }

    if ($args{"month"})
    {
	my $month = (localtime ($args{"date"}))[4];
	$FILE .= ".month" . $month % $args{"month"};
    }

    if ($args{"week"})
    {
	my $week = strftime ('%W', localtime ($args{"date"}));
	$FILE .= ".week" . $week % $args{"week"};
    }

    my ($pager, $name, $earliest, $latest, $p);

    my $section = "";
    my $section_name = "";
    my $text_gather = undef;

    my @week_headers = ( "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" );
    my @week_header_order;

    if (!open (IN, $FILE))
    {
    	$self->{"error"} = "open $FILE failed: $!";
	return undef;
    }

    push @{$self->{"loaded_files"}}, $FILE;

    while (<IN>)
    {
    	s/(\x0d\x0a|\x0a)$//;

	next if (/^\s*#/);
	next if ($section ne "text" && /^\s*$/);

	if ($section eq "" && /^\s*begin\s+(\S+)\s*(\S*)\s*$/)
	{
	    $section = $1;
	    $section_name = $2;
	    $text_gather = "";
	    next;
	}

	elsif ($section ne "" && (/^\s*end\s+(\S+)\s*$/))
	{
	    if ($section ne $1)
	    {
	    	$self->{"error"} = "$FILE: end section does not match begin line $.";
		last;
	    }

	    else
	    {
	    	$section = "";
		$section_name = "";
		$text_gather = "";
		next;
	    }
	}

	elsif ($section ne "")
	{
	    #
	    # person
	    #
	    if ($section eq "person" && /^\s*(\S+)\s*(.*)\s*$/)
	    {
		my ($type, $val) = ($1, $2);
		$type =~ tr/A-Z/a-z/;

		push @{$self->{"people"}->{$section_name}->{$type}}, $val;

		next;
	    }

	    #
	    # text
	    #
	    elsif ($section eq "text")
	    {
	    	$self->{"text"}->{$section_name} .= "$_\n";
		next;
	    }

	    else
	    {
	    	$self->{"error"} = "$FILE: unknown format within section line $.";
		last;
	    }
	}


	#
	# variables
	#
	elsif ($section eq "" && /^\s* "? \s* (\S+) \s* = \s* (.*)$/x)
	{
	    my ($var, $val) = ($1, $2);
	    $val =~ s/[",]*$//;
	    $self->{"vars"}->{$var} = $val;

	    #
	    # if this is an "override" schedule and
	    # the date is not within the applicable range,
	    # then skip over it
	    #
	    if ($var =~ /^override$/i && ! _in_range ($args{"date"}, $val))
	    {
	    	last;
	    }

	    next;
	}

	#
    	# no match, assume this is the schedule portion
	#
	my (@c) = split (/\s*,\s*/, $_, 8);

	#
	# csv format
	#
	if (@c == 8)
	{
	    my ($time_range, @weekday_people) = @c;

	    #
	    # header row
	    #
	    if ($time_range =~ /^\s*$/ && $weekday_people[0] =~ /^(mon|tue|wed|thu|fri|sat|sun)/i)
	    {
		my %day_order = (
			"Sun" => 0,
			"Mon" => 1,
			"Tue" => 2,
			"Wed" => 3,
			"Thu" => 4,
			"Fri" => 5,
			"Sat" => 6,
		);

		for (my $i=0; $i < @weekday_people; $i++)
		{
		    for (my $j = 0; $j < @week_headers; $j++)
		    {
			if ($weekday_people[$i] =~ /^$week_headers[$j]/i)
			{
			    $week_header_order[$i] = $day_order{$week_headers[$j]};
			    last;
			}
		    }
		}

		next;
	    }

	    #
	    # hour row
	    #
	    my ($s1, $s2) = _range ($time_range);

	    if (!defined $s1)
	    {
		$self->{"error"} = "time range is not appropriate, line $.";
		last;
	    }

	    if (($s2 - $s1 + 1) < $self->{"span"})
	    {
	    	$self->{"span"} = $s2 - $s1 + 1;
	    }

	    $self->{"earliest"} = $s1 if ($s1 < $self->{"earliest"});

	    $self->{"latest"} = $s2 if ($s2 > $self->{"latest"});

	    #
	    # for each day, fill in the schedule
	    #
	    for (my $i = 0; $i < @weekday_people; $i++)
	    {
		my $replaced = 0;

		#
		# skip over empty entries
		#
		next if ($weekday_people[$i] =~ /^\s*$/);

		#
		# if the time range is already in the list, replace it
		#
 		if (@{$self->{"sched"}} > 0 && 
		    defined ($self->{"sched"}->[$week_header_order[$i]]))
 		{
 		    for (my $j = 0; $j < @{$self->{"sched"}->[$week_header_order[$i]]}; $j++)
 		    {
 			# @{$self->{"sched"}->[day#, 0=sunday]->[hour range element]} = [0, 59, "name"]
 
 			if ($self->{"sched"}->[$week_header_order[$i]]->[$j]->[0] eq $s1 &&
 			    $self->{"sched"}->[$week_header_order[$i]]->[$j]->[1] eq $s2)
 			{
 			    $replaced = 1;
 			    $self->{"sched"}->[$week_header_order[$i]]->[$j] = [$s1, $s2, $weekday_people[$i]];
 			}
 		    }
 		}

		#
		# if the entry didn't replace a pre-existing
		# one, then append it to the list
		#
		if (!$replaced)
		{
		    push @{$self->{"sched"}->[$week_header_order[$i]]},
			    [$s1, $s2, $weekday_people[$i]];
	    	}
	    }

	}

	#
	# unknown format
	#
	else
	{
	    next;
	}
    }

    #
    # error from inside loop
    #
    if ($self->{"error"} ne "")
    {
    	close (IN);
	return undef;
    }

    if (!close (IN))
    {
	$self->{"error"} = "close: $!";
	return undef;
    }

    #
    # fill in defaults for text which was not
    # defined in the file
    #
    foreach my $key (keys %{$self->{"text-defaults"}})
    {
    	if ($self->{"text"}->{$key} eq "")
	{
	    $self->{"text"}->{$key} = $self->{"text-defaults"}->{$key};
	}
    }

    #
    # sort entries for each day in ascending order
    #
    for (my $day = 0; $day < @{$self->{"sched"}}; $day++)
    {
	my @a = sort
	    {
	    	$a->[0] <=> $b->[0];
	    }
	    @{$self->{"sched"}->[$day]};

    	@{$self->{"sched"}->[$day]} = @a;
    }

    return "";
}



sub rotation
{
    my $self = shift;
    my (%args) = @_;

    $self->{"error"} = "";

    $args{"date"} = time if ($args{"date"} == 0);

    my $week = strftime ('%W', localtime ($args{"date"}));
    my $month = strftime ('%m', localtime ($args{"date"})) - 1;

    if ($args{"week"})
    {
    	$week = $week % $args{"week"};
    }

    if ($args{"month"})
    {
    	$month = $month % $args{"month"};
    }

    return ($week, $month);
}


sub setvar
{
    my $self = shift;
    my %vars = @_;

    $self->{"error"} = "";

    foreach my $var (keys %vars)
    {
    	$self->{"vars"}->{$var} = $vars{$var};
    }
}


sub getvar
{
    my $self = shift;
    my $var = shift;

    return $self->{"vars"}->{$var};
}


#
# takes a range string as an argument, returns
# undef if there is an error with the syntax or
# returns two integers, one for the first part
# of the range and the other for the second.
#
# if the range string only includes one component,
# it is assumed that the intended range is
# from that hour until :59
#
sub _range
{
    my $range = shift;

    if ($range !~ /^
	\s*
	#
	# first hour portion
	#
	(\d?\d:\d\d)

	#
	# optional second hour portion
	#
	(\s* - \s* \d?\d:\d\d)?
	\s*$/ix)
    {
    	return undef;
    }

    my ($r1, $r2) = ($1, $2);
    $r2 =~ s/^\s*-\s*//;

    my ($r1h, $r1m) = split (/:/, $r1);
    my ($r2h, $r2m) = split (/:/, $r2);

    return undef if ($r1h > 23 || $r2h > 23);

    if (defined $r2h)
    {
	return undef if ($r1m > 59 || $r2m > 59);
	return undef if ($r2h < $r1h);
    }

    if (!defined $r2h)
    {
    	return (
	    $r1h * 60 + $r1m,
	    $r1h * 60 + 59,
	);
    }

    return (
    	$r1h * 60 + $r1m,
	$r2h * 60 + $r2m,
    );
}


sub min_format
{
    my $self = shift;
    my $min = shift;

    my $h = int ($min / 60);
    my $m = $min - $h * 60;

    sprintf ("%02d:%02d", $h, $m);
}



sub substitute_text
{
    my $self = shift;

    my %t = (
    	"date" => scalar (localtime (time)),
	"files" => join (",", @{$self->{"loaded_files"}}),
    );

    foreach my $txt (keys %{$self->{"text"}})
    {
    	foreach my $var (keys %{$self->{"oncall-now"}})
	{
	    $self->{"text"}->{$txt} =~ s/\$\{$var\}/$self->{"oncall-now"}->{$var}/gm;
	}

	foreach my $var (keys %t)
	{
	    $self->{"text"}->{$txt} =~ s/\$\{$var\}/$t{$var}/gm;
	}

	foreach my $var (keys %{$self->{"vars"}})
	{
	    $self->{"text"}->{$txt} =~ s/\$\{$var\}/$self->{"vars"}->{$var}/gm;
	}

	$self->{"text"}->{$txt} =~ s/\$\{[a-zA-Z0-9_-]+\}/n\/a/gm;
    }
}


sub _in_range
{
    my ($date, $range) = @_;

    my ($begin, $end) = split (/\s*through\s*/, $range, 2);

    return 0 if ParseDate ($begin) eq "";

    return 0 if ParseDate ($end) eq "";

    if ($date >= UnixDate ($begin, '%s') && $date <= UnixDate ($end, '%s'))
    {
    	return 1;
    }

    return 0;
}

=head1 NAME

Schedule::Oncall - Methods for managing an on-call schedule

=head1 SYNOPSIS

    use Schedule::Oncall;

=head1 DESCRIPTION

    Schedule::Oncall provides methods to manipulate an on-call schedule.
    One or more tables of schedules can be maintained, loaded, and
    searched.  An on-call table is composed of seven days, where each
    day has a list of minute ranges which correspond to a particular person.

    Information such as email address, pager number, etc. may be stored in
    the schedule configuration file. Simple variable assignments may also
    be made. Other textual information may be stored in the schedule in
    order to assist other applications (e.g., html headers or email body
    text), and variables substitution may occur within the text blocks.

    Schedule files may be chosen based on weekly or monthly rotations,
    relative to the first week or month of the year. Weekly schedules
    begin on a Monday and end on a Sunday, the same as strftime(3)'s
    "%W" format. Each rotation is stored in a separate file, and the
    appropriate rotation is chosen at load time.


=head1 METHODS

=over 4

=item new

    my $sched = new Schedule::Oncall;

    Returns a new Schedule::Oncall object.


=item error

    my $error = $sched->error;

    The error string as returned by the last method invoked. An empty
    string ("") means no error.


=item load

=over 1

=item B<USAGE>

    $sched->load (
    	"dir"		=> "/path",
	"file"		=> "filename",
	"date"		=> num,
	"week"		=> num,
	"month"		=> num,
    );

    if ($sched->error ne "")
    {
    	print STDERR "error loading schedule: " . $sched->error . "\n";
    }

    Load a schedule into a schedule object. This may be called multiple
    consecutive times, and the schedules will be overlayed.

    "dir" is the path to the schedule files. If unspecified it defaults to
    "./".

    "file" is the filename of a schedule to load. If it is an absolute path,
    then that path overrides "dir". If it is a simple filename or a relative
    path, it is appended to "dir".

    "date" is the time (as integer seconds since the Epoch (00:00:00 UTC,
    January 1, 1970). If unspecified it defaults to the current time.

    "month" is an integer which is used to control which monthly schedule to
    load. The month number is the month of the year (jan is 0) modulo "month".
    "file" is appended with ".monthN" where "N" is the result of the modulo.

    "week" is the week version of "month". Calculations are performed with the
    week number instead of the month number. The first week of the year is
    numbered "1" and begins on the first monday of the year.  Days prior to
    that reside in week 0. For example, Jan 1-3 1999 are week 0, and jan 4 1999
    begins week 1. See "cal 1 1999".

    Both monthly and weekly schedule rotations are supported if both "week" and
    "month" are supplied. The resulting filename will resemble
    "filename.month5.week2".

    undef is returned if there is an error, and the description of the error is
    stored in $sched->error.

    If this method is called successive times to load different schedules, the
    schedules are overlayed.

=item B<FILE FORMAT>

	The format of the schedule file is somewhat free-form.	Blank
	lines and lines beginning with a "#" are ignored.  It consists
	of person definitions, text definitions, variable assignments,
	and schedule definitions, in any order. It is recommended to
	keep the schedule definition at the end of the file for readability
	purposes.

	A person definition looks like this:

	begin person doej
	    fullname John Doe
	    pager 408-555-1212
	    cell 555-555-1212
	    email doej@domain.com
	    email doej@otherdomain.com
	end person

	Indentation is not significant, but it helps readability.
	There can be any number of contact types ("email", "pager",
	etc.) and each type can have multiple entries. There are
	no pre-defined contact types, but as a convention there
	should be "email", "pager", "fullname", "cell", "workphone",
	and "homephone".

	Text definitions are used to store configuration data for
	applications based on 

	A text definition looks like this:

	begin text email-response
	From: mis@domain.com
	To: __SUBMITTER__

	We have received your submittion to the oncall alias.
	Someone will respond soon.

	end text

	Variable definitions are also used to store configuration
	information, and may only span one line, like this:

	VARIABLE = value

	Text definitions may undergo variable substitutions.
	Substitions are invoked by ${variable}. The B<substitute_text>
	method performs the actual substitutions.

	Schedule definitions show who is on call at what times.
	The format is vaguely compatible with a comma-separated-values
	file, like this:

	,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday
	08:00,joe,jon,jon,jon,fred,bob
	09:00,phil,marty,pat,jon,jon,jon,jon

	This allows schedules to be imported into spreadsheet applications
	and edited there. The above example shows that "pat" is oncall from
	09:00-09:59 on Wednesday morning. Empty entries are ignored rather than
	inserting a null string for the corresponding time slot.  This allows
	multiple schedules to be overlayed for the purpose of implementing
	temporary "substitute" schedules.

	If during the parsing of the schedule files this routine finds a variable
	definition "override = (begin date) through (end date)", and the date
	argument passed to this method falls within those two override dates, then
	parsing of the file is terminated at the point where the variable is
	defined.  This allows the specification of temporary schedules which are
	applicable to only a particular time frame. One application is for modified
	schedules when individuals go on vacation.

	The first line with a blank first column and day names is considered
	the title line, and it defines the day order in which the following
	rows are in.

	Hours are in 24-hour format. They may be a single hour (such as "08:00"
	or "08:30"), which implies the entry begins at the time listed and
	continues until the last minute of that hour, e.g. 08:00 through 08:59.
	Ranges are also acceptable, like this:

	08:00-08:29,joe,joe,joe,...
	08:30-08:59,fred,fred,fred,...

	Ranges must begin and end on the same day. The second time of the
	range must be later than the first part (i.e. a range like
	"23:30-00:30" is invalid).

=back

	One "schedule" may be broken up into separate files for
	convenience, and each file can be loaded separately. For example,
	it might be a good idea to keep the people, text, and variable
	definitions in their own file, and the actual schedule in its
	own file for easier editing.


=item oncall

    my $person = $sched->oncall (time);

    Returns the name of the person who is on call at "time", given
    the currently loaded schedule.  "time" is seconds since the Epoch,
    or the current time if unspecified.

    The $sref->{"oncall-now"} structure is also initialized with
    all of the personal data for that username collected in the
    configuration file. If the on-call person is found to be a null
    string, $sref->{"oncall->now"}->{"username"} is set to "nobody",
    otherwise it is set to the username from the schedule. Variables
    with multiple values (e.g. two email addresses specified) will be
    joined with ",".

    undef is returned if there is an error or if nobody is on call.
    $sched->error is set to the error description.


=item info

return info about a person

for each person some personal info is stored
returns:

( "pager" => ["pager1", "pager2", ...],
  "email" => ["email1", "email2", ...],
  "cell"  => ["cell1", "cell2", ...],
  "fullname" => "full name",
  "etc" => "etc", ...)

returns undef on error.


=item var

    my $val = $sched->var ("varname");

    Returns the value of "varname" which was set in the configuration
    file, or undef if the variable does not exist.


=item rotation

    my ($week, $month) = $sched->rotation (
    	"week" => 4,
	"month" => 4,
    );

    returns the current week and month rotation


=item schedule

    Returns the currently loaded schedule as an array with each element
    representing the hourly schedule for that day, in list form. The
    first element is Sunday. For example:

    ([[0, 59, "person1"], [60, 119, "person2"], ...], [[0, 59, "person3"], ...], ...)

    describes a schedule where "person1" is on call Sunday from midnight
    until 1am, "person2" is on call from 1am until 2am, "person3" is on
    on call from midnight until 1am on Monday, etc.


=item min_format

    Given a minute of the day, returns a formatted time
    such as hh:mm.


=item substitute_text

    Perform variable expansion on the text collected from
    a config file. All the variables defined in the config
    file are substituted, along with any settings of
    $self->{"oncall-now"} set by invoking the B<oncall> method,
    "date" (set to localtime(time)), and "files" set to a
    comma-separated list of files read by the B<load> method.
    Variables located in the text sections which have no
    definition are substituted with "n/a".


=item setvar


=item getvar


=back

=head1 SEE ALSO

time(2)

=head1 HISTORY

none.

=cut
