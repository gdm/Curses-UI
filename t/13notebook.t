# -*- perl -*-
# $Id: 13notebook.t,v 1.4 2005/03/18 10:10:51 mthies2s Exp $

use Test::More tests => 24;
use FindBin;
use lib "$FindBin::RealBin/fakelib";
use lib "$FindBin::RealBin/../lib";
use Curses::UI;

# Tests 1: module load.
BEGIN { 
    $| = 1;
    # Ensure Term::ReadKey doesn't fail to get the screen size.
    $ENV{LINES} = 25;
    $ENV{COLUMNS} = 80;

    use_ok('Curses::UI::Notebook');
}

my $debug = 0;

my $cui = new Curses::UI (
    -clear_on_exit => 0,
    -debug => $debug,
);
$cui->leave_curses();

my $win = $cui->add(undef, 'Window');
exit unless $win;

# Tests 2-4: notebook object creation.
my $nb1 = $win->add(undef, 'Notebook');
ok(
    $nb1->isa('Curses::UI::Notebook') &&
    $nb1->{-border} == 1 && $nb1->{-sbborder} == 0 &&
    $nb1->{-padleft} == 0 && $nb1->{-ipadleft} == 1,
    'Initialization w/ defaults'
);

ok(!$nb1->active_page, 'active_page(), w/o pages');

my $nb2 = $win->add(
    undef, 'Notebook',
    -border     => 0,
    -sbborder   => 1,
    -wraparound => 0,
);
ok(
    $nb2->isa('Curses::UI::Notebook') &&
    $nb2->{-border} == 0 && $nb2->{-sbborder} == 1 &&
    $nb2->{-wraparound} == 0,
    'Initialization w/ specific values'
);


# Tests 5-11: page addition.
for (my $i = 1; $i <= 3; $i++) {
    my $page = $nb1->add_page("Page $i");
    ok(
        defined $page && 
        $page->isa('Curses::UI::Window') &&
        scalar(@{$nb1->{-pages}}) == $i,
        "add_page(), page $i, nb1"
    );
}

# nb: with three pages, tab window uses 28 spaces (6/tab for labels, 2/tab 
#     for padding, 1/tab for start border, and 1 for final border) before
#     adding this page.
my $page = $nb1->add_page('=' x ($nb1->{-w} - 28 - 3 + 1));
ok(!$page, 'add_page(), overflow');

for (my $i = 1; $i <= 3; $i++) {
    my $page = $nb2->add_page("Page $i");
    ok(
        defined $page && 
        $page->isa('Curses::UI::Window') &&
        scalar(@{$nb2->{-pages}}) == $i,
        "add_page(), page $i, nb2"
    );
}


# Tests 12-17: page ordering and wraparound.
ok($nb1->active_page eq 'Page 1', 'active_page()');

ok($nb1->first_page eq 'Page 1', 'first_page()');

ok($nb1->last_page eq 'Page 3', 'last_page()');

ok($nb1->prev_page eq 'Page 3', 'prev_page(), w/ wraparound');

ok($nb2->prev_page eq 'Page 1', 'prev_page(), w/o wraparound');

ok($nb1->next_page eq 'Page 2', 'next_page()');


# Tests 18-19: page movement.
ok(
    $nb1->activate_page('Page 3') && $nb1->active_page eq 'Page 3', 
    'active_page(), nb1'
);

ok(
    $nb2->activate_page('Page 3') && $nb2->active_page eq 'Page 3', 
    'active_page(), nb2'
);


# Tests 20-21: wraparound (at end).
ok($nb1->next_page eq 'Page 1', 'next_page(), w/ wraparound');

ok($nb2->next_page eq 'Page 3', 'next_page() w/o wraparound');


# Tests 22-24: page deletion.
$nb1->delete_page('Page 1');
ok(
    $nb1->first_page eq 'Page 2' && 
    scalar(@{$nb1->{-pages}}) == 2,
    'delete_page()'
);

# - deleting active page should make Page 3 active.
$nb1->activate_page('Page 2');
$nb1->delete_page('Page 2');
ok(
    $nb1->active_page eq 'Page 3' && 
    $nb1->next_page eq 'Page 3' && 
    scalar(@{$nb1->{-pages}}) == 1,
    'delete_page(), active page'
);

$nb1->delete_page('Page 3');
ok(
    !$nb1->active_page && 
    scalar(@{$nb1->{-pages}}) == 0,
    'delete_page(), final page'
);
