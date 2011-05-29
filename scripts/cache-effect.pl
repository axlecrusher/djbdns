#!/usr/local/bin/perl -w
# This came from <URL:http://code.dogmap.org./djbdns/>.
# See also <URL:http://freshmeat.net/dnscacheproc>.

use strict;
use warnings;
use IO::Handle;
use IO::File;
use POSIX qw(&ceil);

@ARGV or die("usage: cache-effect /service/dnscache [...]\n");

my $file=IO::File->new();
my $dir=IO::Handle->new();

foreach my $service (@ARGV) {
  my $path=$service.'/env/CACHESIZE';
  $file->open($path, O_RDONLY)
      or die('unable to open "', $path, '": ', $!, "\n");
  my $cachesize=$file->getline();
  $file->close();

  $path=$service.'/log/main/';
  opendir($dir, $path)
      or die('unable to opendir "', $path, '": ', $!, "\n");
  my @logs=readdir($dir);
  closedir($dir);

  my ($first_stats, $last_stats)=(undef, undef);
  foreach my $log (reverse(sort(@logs))) {
    next unless $log eq 'current' or substr($log, 0, 1) eq '@';
    $file->open($path.$log)
        or die('unable to open "', $path.$log, '": ', $!, "\n");
    my ($stats, $file_first_stats, $line, $found_restart)=
        (undef, undef, undef, undef);
    while (defined($line=$file->getline())) {
      if ($line=~/^@[0-9a-f]{24} starting\n\z/) {
        $file_first_stats=$stats=undef;
        $found_restart=1;
        next;
      }
      next unless $line=~/^@([0-9a-f]{16})[0-9a-f]{8} stats [0-9]+ ([0-9]+) [0-9]+ [0-9]+\n\z/;
      my $prev_stats=$stats;
      $stats=[$1, $2];
      if (not defined($prev_stats)) {
        $file_first_stats=$stats;
      } elsif ($stats->[1]<$prev_stats->[1]) {
        $file_first_stats=$stats;
        $found_restart=1;
      }
    }
    $file->close();
    $last_stats=$stats if not defined($last_stats);
    $first_stats=$file_first_stats if defined($file_first_stats);
    last if defined($found_restart);
  }

  print($service, ":\n");
  unless (defined($last_stats) and defined($first_stats)) {
    print("not enough log data.\n");
    next;
  }

  my $motion=$last_stats->[1]-$first_stats->[1];
  my $span=hex(substr($last_stats ->[0], 1))
          -hex(substr($first_stats->[0], 1));
  my $days=sprintf('%.2g', $span/86400);
  my $lifetime=sprintf('%.2g', $cachesize*$span/(86400*$motion));
  my $size3=ceil(3*$cachesize/$lifetime);
  my $size7=ceil(7*$cachesize/$lifetime);
  print(<<"EOT");
Over the last $days days of logs, records were forced out of the cache
after $lifetime days.  Most records expire after 3 days or less anyway, and
dnscache always expires records after 7 days.
If you set CACHESIZE to $size3, dnscache will not be forced to throw
away records until they are 3 days old.
If you set CACHESIZE to $size7, dnscache will not be forced to throw
away records until they are 7 days old.
EOT
}
