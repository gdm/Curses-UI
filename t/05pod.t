# -*- perl -*-
# Testing Plain old Documentation for Curses::UI
# 2004 (c) by Marcus Thiesen
# marcus@cpan.org

use strict;
use FindBin;
use File::Find;
use Test::More;
use Test::Pod (tests => 40);


sub wanted {
    if ($File::Find::name =~ /\.pm$/) {
	pod_file_ok( "$File::Find::name", "POD Documentation in $_" );
    }
}

my $dir = "$FindBin::RealBin/../lib/Curses/";

find(\&wanted, ($dir));

