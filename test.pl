exit;

use Schedule::Oncall;

use strict;

my $s = new Schedule::Oncall;

if (!defined $s->load ("file" =>  "test-sched"))
{
    die "failed: " . $s->{"error"} . "\n";
}

if (!defined $s->load ("file" =>  "test-sched-override"))
{
    die "failed: " . $s->{"error"} . "\n";
}

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

my @a = $s->schedule;

my @day_list = qw (sun mon tue wed thu fri sat);

for (my $day = 0; $day < @a; $day++)
{
    foreach my $entry (@{$a[$day]})
    {
	my $hstart = $s->min_format ($entry->[0]);
	my $hend = $s->min_format ($entry->[1]);

	print "$day_list[$day] $hstart-$hend $entry->[2]\n";
    }

    print "\n";
}

exit;

__END__
for (my $day = 0; $day < @a; $day++)
{
    print "day $day\n";
    print Dumper ($a[$day]), "\n";
}

die;

print Dumper ($s), "\n";

my $inf = $s->info ("trockij");

print Dumper ($inf), "\n";

my $on = $s->oncall (time);

print "[$on] on call\n";

my ($w, $m) = $s->rotation ("week" => 4, "month" => 4);

print "week $w month $m\n";
