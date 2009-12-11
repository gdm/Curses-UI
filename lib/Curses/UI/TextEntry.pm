# ----------------------------------------------------------------------
# Curses::UI::TextEntry
#
# (c) 2001-2002 by Maurice Makaay. All rights reserved.
# This file is part of Curses::UI. Curses::UI is free software.
# You can redistribute it and/or modify it under the same terms
# as perl itself.
#
# e-mail: maurice@gitaar.net
# ----------------------------------------------------------------------

package Curses::UI::TextEntry;

use strict;
use Curses;
use Curses::UI::TextEditor;

use vars qw($VERSION @ISA);
@ISA = qw(Curses::UI::TextEditor);
$VERSION = '1.00';
	
sub new ()
{
	my $class = shift;

	my %args = ( 
		-undolevels	 => 20,	# number of undolevels. 0 = infinite
		-homeonreturn    => 1,	# cursor to homepos on return?
		@_,
		-singleline	 => 1,	# single line mode or not?
		-showhardreturns => 0,	# show hard returns with diamond char?
	);

	# Create the entry.
	my $this = $class->SUPER::new( %args);

	# There is no reason to show overflow symbols if no
	# more characters than the available width can be
	# added (the screen would wrap and after that
	# typing would be impossible).
	if ($this->{-maxlength} and $this->screenwidth > $this->{-maxlength}) {
		$this->{-showoverflow} = 0;
	}

	# Setup bindings.
        $this->clear_binding('return');
        $this->set_binding('return', KEY_ENTER(), "\t" );

	return bless $this, $class;
}

1;

__END__


=pod

=head1 NAME

Curses::UI::TextEntry - Create and manipulate textentry widgets

=head1 SYNOPSIS

    use Curses::UI;
    my $cui = new Curses::UI;
    my $win = $cui->add('window_id', 'Window');

    my $textentry = $win->add( 
        'mytextentry', 'TextEntry',
        -password => '*',
    );

    $textentry->focus();
    my $text = $textentry->get();


=head1 DESCRIPTION

Curses::UI::TextEntry is a widget that can be used 
to create a textentry widget. This class is
derived from Curses::UI::TextEditor. The
only special thing about this class is that the 
B<-singleline> option is forced to a true value. 
So for the usage of Curses::UI::TextEntry see
L<Curses::UI::TextEditor|Curses::UI::TextEditor>).




=head1 SEE ALSO

L<Curses::UI|Curses::UI>, 
L<Curses::UI::TextEditor|Curses::UI::TextEditor>, 




=head1 AUTHOR

Copyright (c) 2001-2002 Maurice Makaay. All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty. It may be used, redistributed and/or modified
under the same terms as perl itself.

=end

