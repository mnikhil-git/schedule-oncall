use strict;
use Test;

BEGIN { plan tests => 6 }

use Schedule::Oncall;

my $s = new Schedule::Oncall;

#
# test 1
#
if (defined $s)
{
    ok (1);
}

else
{
    ok (0, 1, "create instance of Schedule::Oncall")
}


#
# test 2
#
if (!defined $s->load ("file" =>  "test-sched"))
{
    ok (0, 1, "load test-sched: " . $s->{"error"});
}

ok (1);

#
# test 3
#
# tue 10:44
my $person = $s->oncall (1031064279);

ok ($person, "johnd", "lookup of oncall");

#
# test 4
#
if (!defined $s->load ("file" =>  "test-sched-override"))
{
    ok (0, 1, "load override " . $s->{"error"});
}

ok (1);

#
# test 5
#
# tue 10:44
my $person = $s->oncall (1031064279);

ok ($person, "gwb", "lookup of oncall overlay");

#
# test 6
#
my %info = $s->info ("gwb");

ok ($info{"email"}->[0], "gwb\@x_yyz.com", "email info for gwb");

__END__

print $s->oncall, " is on call at this time\n";

my %info = $s->info ($s->oncall); 

foreach my $key (sort keys %info)
{
	print "   $key = ";
	for (my $i=0; $i<@{$info{$key}}; $i++)
	{
	    print "[$info{$key}->[$i]] ";
	}
	print "\n";
}

print "\n";
