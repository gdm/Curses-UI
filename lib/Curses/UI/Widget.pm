# ----------------------------------------------------------------------
# Curses::UI::Widget
#
# (c) 2001-2002 by Maurice Makaay. All rights reserved.
# This file is part of Curses::UI. Curses::UI is free software.
# You can redistribute it and/or modify it under the same terms
# as perl itself.
#
# e-mail: maurice@gitaar.net
# ----------------------------------------------------------------------

package Curses::UI::Widget;

use strict;
use Carp qw(confess);
use Term::ReadKey;
use Curses;
use Curses::UI::Common;
require Exporter;

use vars qw($VERSION @ISA @EXPORT);
@ISA = qw(Exporter Curses::UI::Common);
@EXPORT = qw(
	height_by_windowscrheight
	width_by_windowscrwidth
	process_padding
);
$VERSION = '1.19';

sub new ()
{
	my $class = shift;

        my %userargs = @_;
        keys_to_lowercase(\%userargs);

	my %args = ( 
		-parent		=> undef, 	# the parent object
		-assubwin	=> 1,		# 0 = no, 1 = yes, create as subwindow? 
		-x		=> 0,		# horizontal position (rel. to -parent)
		-y		=> 0,		# vertical position (rel. to -parent)
		-width		=> undef,	# horizontal size 
		-height		=> undef,	# vertical size
		-border		=> 0,		# add a border?
		-sbborder	=> 0,		# add square bracket border?

		-titlefullwidth => 0,		# full width for title?
		-titlereverse   => 1,		# reverse chars for title? 
		-title		=> undef,	# A title to add to the widget (only for 
						# -border = 1)

						# padding outside widget
		-pad		=> undef,	# all over padding
		-padright	=> undef,	# free space on the right side
		-padleft	=> undef,	# free space on the left side
		-padtop		=> undef,	# free space above
		-padbottom	=> undef,	# free space below

						# padding inside widget
		-ipad		=> undef,	# all over padding
		-ipadright	=> undef,	# free space on the right side
		-ipadleft	=> undef,	# free space on the left side
		-ipadtop	=> undef,	# free space above
		-ipadbottom	=> undef,	# free space below

		-vscrollbar	=> 0,    	# vert. scrollbar (top/bottom)
		-vscrolllen     => 0,		# total number of rows
		-vscrollpos     => 0,		# current row position

		-hscrollbar	=> 0,    	# hor. scrollbar (left/right)
		-hscrolllen     => 0,		# total number of columns
		-hscrollpos     => 0,		# current column position 

		-onfocus	=> undef,	# onFocus event handler
		-onblur		=> undef,	# onBlur event handler
		-intellidraw    => 1,   	# Support intellidraw()?

		%userargs,
	
		-scr		=> undef,	# generic window handler
		-focus		=> 0,	  	# has the widget focus?	
	);

	# Allow the value -1 for using the full width and/or
	# height for the widget.
	$args{-width} = undef 
		if defined $args{-width} and $args{-width} == -1;
	$args{-height} = undef 
		if defined $args{-height} and $args{-height} == -1;

	confess "Missing parameter: -parent" 
		if $args{-assubwin} and not defined $args{-parent};
	
	# Allow a square bracket border only if 
	# a normal border (-border) is disabled.
	$args{-sbborder} = 0 if $args{-sbborder} and $args{-border};
	
	# Bless you! (so we can call the layout function).
	my $this = bless \%args, $class;

	$this->layout;

	return $this;
}

sub layout()
{
	my $this = shift;
		
	return $this if $Curses::UI::screen_too_small;
	$this->process_padding;
	
	# -------------------------------------------------------
	# Delete windows 
	# -------------------------------------------------------

	foreach (qw(-windowscr -borderscr)) 
	{
	    if (defined $this->{$_})
  	    {	
		$this->{$_}->delwin;
		delete $this->{$_};
	    }
	}
	delete $this->{-scr};
        
	# -------------------------------------------------------
	# Compute the space that we have for the widget.
	# -------------------------------------------------------

	if ($this->{-assubwin} and defined $this->{-parent}
	    and not $this->isa('Curses::UI::Menubar')) 
	{
		$this->{-parentdata} = $this->{-parent}->windowparameters;
	} else {
		$this->{-parentdata} = {
			'-w' => $ENV{COLS},
			'-h' => $ENV{LINES},
			'-x' => 0,
			'-y' => 0,
		};
	}

	foreach (qw(x y)) {
   	    if (not defined $this->{"-$_"}) {$this->{"-$_"} = 0} 
	    if ($this->{"-$_"} >= 0) {
		$this->{"-real$_"} = $this->{"-$_"};
	    } else {
		my $pv = ($_ eq 'x' ? '-w' : '-h');
		$this->{"-real$_"} = $this->{-parentdata}->{$pv} 
		 		   + $this->{"-$_"} + 1;
	    }
	}

	my $w = $this->{-parentdata}->{-w};
	my $h = $this->{-parentdata}->{-h};

	my $cor_h = $this->{-y};
	$cor_h = abs($this->{-y}+1) if $cor_h < 0;
	my $cor_w = $this->{-x};
	$cor_w = abs($this->{-x}+1) if $cor_w < 0;
	
	my $avail_h = $h - $cor_h;
	my $avail_w = $w - $cor_w;
	
	# Compute horizontal widget size and adjust if neccessary.
	my $min_w = ($this->{-border} ? 2 : 0) 
	          + ($this->{-sbborder} ? 2 : 0) 
	          + (defined $this->{-vscrollbar} ? 1 : 0) 
		  + $this->{-padleft} + $this->{-padright}; 
	my $width = (defined $this->{-width} ? $this->{-width} : $avail_w);
	$width = $min_w if $width < $min_w; 
	$width = $avail_w if $width > $avail_w; 

	# Compute vertical widget size and adjust if neccessary.
	my $min_h = ($this->{-border} ? 2 : 0)
	          + ($this->{-hscrollbar} ? 1 : 0) 
	          + (defined $this->{-hscrollbar} ? 1 : 0) 
		  + $this->{-padtop} + $this->{-padbottom};
	my $height = (defined $this->{-height} ? $this->{-height} : $avail_h);
	$height = $min_h   if $height < $min_h;
	$height = $avail_h if $height > $avail_h;

	# Check if the widget fits in the window.
	if ($width > $avail_w or $height > $avail_h 
	    or $width == 0 or $height == 0) {
		$Curses::UI::screen_too_small++;
		return $this;
	}

	$this->{-w}  = $width;
	$this->{-h}  = $height;

	if ($this->{-x} < 0) { $this->{-realx} -= $width }
	if ($this->{-y} < 0) { $this->{-realy} -= $height }
	
	# Take care of padding for the border.
	$this->{-bw} = $width - $this->{-padleft} - $this->{-padright};
	$this->{-bh} = $height - $this->{-padtop} - $this->{-padbottom};
	$this->{-bx} = $this->{-realx} + $this->{-padleft};
	$this->{-by} = $this->{-realy} + $this->{-padtop};

	# -------------------------------------------------------
	# Create a window for the widget border, if a border 
	# and/or scrollbars are wanted.
	# -------------------------------------------------------

	if ($this->{-border} or $this->{-sbborder} 
	    or $this->{-vscrollbar} or $this->{-hscrollbar}) 
	{
		my @args = ($this->{-bh}, $this->{-bw},
			    $this->{-parentdata}->{-y} + $this->{-by},
			    $this->{-parentdata}->{-x} + $this->{-bx});

		if ($this->{-assubwin}) {
			$this->{-borderscr} = 
				$this->{-parent}->{-windowscr}->subwin(@args);
		} else {
			$this->{-borderscr} = newwin(@args);
		}

		unless (defined $this->{-borderscr}) 
		{
			$Curses::UI::screen_too_small++;
			return $this;
		}

		$this->{-scr} = $this->{-borderscr};
	}

	# -------------------------------------------------------
	# Create screen region
	# -------------------------------------------------------

	$this->{-sh}  = $this->{-bh} - $this->{-ipadtop} 
		        - $this->{-ipadbottom} - ($this->{-border}? 2 : 0)
			- (not $this->{-border} and $this->{-hscrollbar} ? 1 : 0);
	$this->{-sw}  = $this->{-bw} - $this->{-ipadleft} 
		        - $this->{-ipadright} - ($this->{-border}? 2 : 0)
		        - ($this->{-sbborder}? 2 : 0)
			- (not $this->{-border}
			   and $this->{-vscrollbar} ? 1 : 0);
	$this->{-sy}  = $this->{-by} + $this->{-ipadtop} + ($this->{-border}?1:0)
			+ (not $this->{-border} 
                           and $this->{-hscrollbar} eq 'top' ? 1 : 0);
	$this->{-sx}  = $this->{-bx} + $this->{-ipadleft} 
			+ ($this->{-border}?1:0)
			+ ($this->{-sbborder}?1:0)
			+ (not $this->{-border} 
                           and $this->{-vscrollbar} eq 'left' ? 1 : 0);

	# Check if there is room left for the screen.
	if ($this->{-sw} <= 0 or $this->{-sh} <= 0) {
		$Curses::UI::screen_too_small++;
		return $this;
	}

	# Create a window for the data.
	my @args = ($this->{-sh}, $this->{-sw},
	   	    $this->{-parentdata}->{-y} + $this->{-sy},
		    $this->{-parentdata}->{-x} + $this->{-sx});
	if ($this->{-assubwin}) {
		$this->{-windowscr} = 
			$this->{-parent}->{-windowscr}->subwin(@args);
	} else {
		$this->{-windowscr} = newwin(@args);
	}
		
	unless (defined $this->{-windowscr}) 
	{
		$Curses::UI::screen_too_small++;
		return $this;
	}

	unless (defined $this->{-borderscr})
	{
		$this->{-scr} = $this->{-windowscr};
		$this->{-bw} = $this->{-sw};
		$this->{-bh} = $this->{-sh};
	}
		
	return $this;
}

sub onFocus($;$) { shift()->set_event('-focus', shift()) }
sub onBlur($;$)  { shift()->set_event('-blur',  shift()) }


sub process_padding($;)
{
	my $this = shift;

	# Process the padding arguments.
	foreach my $type ('-pad','-ipad') {
		if (defined $this->{$type}) {
			foreach my $side ('right','left','top','bottom') {
				$this->{$type . $side} = $this->{$type}
					unless defined $this->{$type . $side};
			}
		}
	}
	foreach my $type ('-pad','-ipad') {
		foreach my $side ('right','left','top','bottom') 
		{
			$this->{$type . $side} = 0
				unless defined $this->{$type . $side};
		}
	}
}

sub width_by_windowscrwidth($@;)
{
        my $width = shift || 0;
	$width = shift if ref $width; # make $this->width... possible.
	my %args = @_;
	
	$width += 2 if $args{-border};  # border
	$width += 2 if $args{-sbborder};  # sbborder
	$width += 1 if (not $args{-border} and not $args{-sbborder}
			and $args{-vscrollbar});
	foreach my $t ("-ipad", "-pad")     # internal + external padding
	{
		if ($args{$t})
		{
                    $width += 2*$args{$t};
                } else {
                    $width += $args{$t . "left"} 
			if defined $args{$t . "left"};
                    $width += $args{$t . "right"} 
			if defined $args{$t . "right"};
                }
	}
	return $width;	
}

sub height_by_windowscrheight($@;)
{
        my $height = shift || 0;
	$height = shift if ref $height; # make $this->height... possible.
	my %args = @_;
	
	$height += 2 if $args{-border};  # border
	$height += 1 if (not $args{-border} and $args{-hscrollbar});
	foreach my $t ("-ipad", "-pad")     # internal + external padding
	{
		if ($args{$t})
		{
                    $height += 2*$args{$t};
                } else {
                    $height += $args{$t . "top"} 
			if defined $args{$t . "top"};
                    $height += $args{$t . "bottom"} 
			if defined $args{$t . "bottom"};
                }
	}
	return $height;	
}

sub width 		{ shift->{-w} }
sub height 		{ shift->{-h} }
sub borderwidth 	{ shift->{-bw} }
sub borderheight 	{ shift->{-bh} }
sub screenwidth 	{ shift->{-sw} }
sub screenheight 	{ shift->{-sh} }

sub title ($;)		
{ 
	my $this = shift;
	$this->{-title} = shift;
	$this->intellidraw;
}

sub windowparameters()
{ 
	my $this = shift;
	my $s = $this->{-windowscr};
	my ($x,$y,$w,$h);

	$s->getbegyx($y, $x);
	$s->getmaxyx($h, $w); 

	my $cor_h = 0;
	my $cor_y = 0;
	if ($this->isa('Curses::UI::Container') and
	    $this->hasa('Curses::UI::Menubar')) {
		$cor_h -= 1;
		$cor_y += 1;
	}
	
	return {
		-w => $w,
		-h => $h + $cor_h, 
		-x => $x,
		-y => $y + $cor_y,
	};
}

# Must be overridden in child class, to make
# the widget focusable.
sub focus()
{ 
	my $this = shift;
	$this->show;
	return ('RETURN',''); 
}

sub draw(;$)
{
	my $this = shift;
	my $no_doupdate = shift || 0;

        # Return immediately if this object is hidden.
        return $this if $this->hidden;

	eval { curs_set(0) }; # not available on every system.

	# Clear the contents of the window.
	for my $y (0..$this->borderheight-1) {
		$this->{-scr}->addstr($y, 1, " "x($this->borderwidth));
	}
	$this->{-scr}->noutrefresh();

	# Do borderstuff?
	if (defined $this->{-borderscr})
	{
	    # Draw a border if needed.
	    if ($this->{-sbborder})  # Square bracket ([,]) border
	    {
		$this->{-borderscr}->attron(A_BOLD) if $this->{-focus};
		my $offset = 1;
		$offset++ if $this->{-vscrollbar};
		for my $y (0 .. $this->{-sh}-1)
		{
		    my $rel_y = $y + $this->{-sy} - $this->{-by};
		    $this->{-borderscr}->addstr($rel_y, 0, '[');
		    $this->{-borderscr}->addstr($rel_y, $this->{-bw}-$offset, ']');
		}
		$this->{-borderscr}->attroff(A_BOLD) if $this->{-focus};
	    }
	    elsif ($this->{-border}) # Normal border
	    {
		$this->{-borderscr}->attron(A_BOLD) if $this->{-focus};
		if ($this->root->compat) {
			$this->{-borderscr}->border(
				'|','|','-','-',
				'+','+','+','+'
			);
		} else {
			$this->{-borderscr}->box(ACS_VLINE, ACS_HLINE);
		}
		$this->{-borderscr}->attroff(A_BOLD) if $this->{-focus};
		
		# Draw a title if needed.
		if (defined $this->{-title})
		{
			$this->{-borderscr}->attron(A_REVERSE) 
				if $this->{-titlereverse};
			if ($this->{-titlefullwidth} 
			    and $this->{-titlereverse}) {
				$this->{-borderscr}->addstr(0, 1, " "x($this->{-bw}-2));
			}
			my $t = $this->{-title};
			my $l = $this->{-bw}-4;
			if ($l < length($t))
			{
				$t = substr($t, 0, $l) if $l < length($t);
				$t =~ s/...$/\.\.\./;
			}
			$this->{-borderscr}->addstr(0, 1, " $t ");
			$this->{-borderscr}->attroff(A_REVERSE);
		}
	    }
        
	    $this->draw_scrollbars();
	    $this->{-borderscr}->noutrefresh();
	}

	doupdate() unless $no_doupdate;
	return $this;
}

sub draw_scrollbars()
{	
	my $this = shift;

	return $this unless defined $this->{-borderscr};

	if ($this->{-vscrollbar} and defined $this->{-vscrolllen}) 
	{

		# Compute the drawing range for the scrollbar.
		my $xpos = $this->{-vscrollbar} eq 'left' 
                         ? 0 : $this->borderwidth-1; 

		my $ypos_min = $this->{-sy}-$this->{-by};
		my $ypos_max = $ypos_min + $this->screenheight - 1;
		my $scrlen = $ypos_max - $ypos_min + 1;
		my $actlen = $this->{-vscrolllen}
			   ? int($scrlen * ($scrlen/($this->{-vscrolllen}))+0.5)
			   : 0;
		$actlen = 1 if not $actlen and $this->{-vscrolllen};
		my $actpos = ($this->{-vscrolllen} and $this->{-vscrollpos})
			   ? int($scrlen*($this->{-vscrollpos}/$this->{-vscrolllen})) + $ypos_min + 1 
			   : $ypos_min;

		# Only let the marker be at the end if the
		# scrollpos is too.
		if ($this->{-vscrollpos}+$scrlen >= $this->{-vscrolllen}) {
			$actpos = $scrlen - $actlen + $ypos_min;
		} else {
			if ($actpos + $actlen >= $scrlen) {
				$actpos--;
			}
		}
		
		# Only let the marker be at the beginning if the
		# scrollpos is too.
		if ($this->{-vscrollpos} == 0) {
			$actpos = $ypos_min;
		} else {
			if ($this->{-vscrollpos} and $actpos <= 0) {
				$actpos = $ypos_min+1;
			}
		}
		
		# Draw the base of the scrollbar, in case
		# there is no border.
		$this->{-borderscr}->attron(A_BOLD) if $this->{-focus};
		$this->{-borderscr}->move($ypos_min, $xpos);
		$this->{-borderscr}->vline(ACS_VLINE,$scrlen);
		if ($this->root->compat) {
			$this->{-borderscr}->vline('|',$scrlen);
		} else {
			$this->{-borderscr}->vline(ACS_VLINE,$scrlen);
		}
		$this->{-borderscr}->attroff(A_BOLD) if $this->{-focus};

		# Should an active region be drawn?
		my $scroll_active = ($this->{-vscrolllen} > $scrlen);
		# Draw scrollbar base, in case there is
		# Draw active region.
		if ($scroll_active) 
		{
			$this->{-borderscr}->attron(A_REVERSE);
			for my $i (0 .. $actlen-1) {
				$this->{-borderscr}->addch($i+$actpos,$xpos," ");
			}
			$this->{-borderscr}->attroff(A_REVERSE);
		}
	}
	
	if ($this->{-hscrollbar} and defined $this->{-hscrolllen})
	{
		# Compute the drawing range for the scrollbar.
		my $ypos = $this->{-hscrollbar} eq 'top' 
                       	? 0 : $this->borderheight-1; 

		my $xpos_min = $this->{-sx}-$this->{-bx};
		my $xpos_max = $xpos_min + $this->screenwidth - 1;
		my $scrlen = $xpos_max - $xpos_min + 1;
		my $actlen = $this->{-hscrolllen}
			   ? int($scrlen * ($scrlen/($this->{-hscrolllen}))+0.5)
			   : 0;
		$actlen = 1 if not $actlen and $this->{-hscrolllen};
		my $actpos = ($this->{-hscrolllen} and $this->{-hscrollpos})
			   ? int($scrlen*($this->{-hscrollpos}/$this->{-hscrolllen})) + $xpos_min + 1 
			   : $xpos_min;

		# Only let the marker be at the end if the
		# scrollpos is too.
		if ($this->{-hscrollpos}+$scrlen >= $this->{-hscrolllen}) {
			$actpos = $scrlen - $actlen + $xpos_min;
		} else {
			if ($actpos + $actlen >= $scrlen) {
				$actpos--;
			}
		}
		
		# Only let the marker be at the beginning if the
		# scrollpos is too.
		if ($this->{-hscrollpos} == 0) {
			$actpos = $xpos_min;
		} else {
			if ($this->{-hscrollpos} and $actpos <= 0) {
				$actpos = $xpos_min+1;
			}
		}
	
		# Draw the base of the scrollbar, in case
		# there is no border.
		$this->{-borderscr}->attron(A_BOLD) if $this->{-focus};
		$this->{-borderscr}->move($ypos, $xpos_min);
		if ($this->root->compat) {
			$this->{-borderscr}->hline('-',$scrlen);
		} else {
			$this->{-borderscr}->hline(ACS_HLINE,$scrlen);
		}
		$this->{-borderscr}->attroff(A_BOLD) if $this->{-focus};

		# Should an active region be drawn?
		my $scroll_active = ($this->{-hscrolllen} > $scrlen);
		# Draw active region.
		if ($scroll_active) 
		{
			$this->{-borderscr}->attron(A_REVERSE);
			for my $i (0 .. $actlen-1) {
				$this->{-borderscr}->addch($ypos, $i+$actpos," ");
			}
			$this->{-borderscr}->attroff(A_REVERSE);
		}
	}
	
	return $this;
}

sub intellidraw(;$)
{
	my $this = shift;

	if ($this->{-intellidraw} and
            not $this->hidden and 
            $this->in_topwindow)
	{
		$this->draw(1);
		doupdate();
	}
	return $this;
}

sub hidden() { shift()->{-hidden} }
sub hide()   { shift()->{-hidden} = 1 }
sub show()   { shift()->{-hidden} = 0 }

sub parentwindow()
{
	my $object = shift;

	until (not defined $object or 
               $object->isa('Curses::UI::Window')) {
		$object = $object->parent;
	}

	return $object;
}

sub in_topwindow()
{
	my $this = shift;
	my $win = $this->parentwindow();
	return unless defined $win;
	$win->is_ontop;
}

# ----------------------------------------------------------------------
# Binding 
# ----------------------------------------------------------------------

sub clear_binding($;)
{
        my $this = shift;
        my $binding = shift;
        my @delete = ();
        while (my ($k,$v) = each %{$this->{-bindings}}) {
                push @delete, $k if $v eq $binding;
        }
        foreach (@delete) {
                delete $this->{-bindings}->{$_};
        }
        return $this;
}

sub set_routine($$;)
{
	my $this = shift;
	my $binding = shift;
	my $routine = shift;
	$this->{-routines}->{$binding} = $routine;
	return $this;
}

sub set_binding($@;)
{
        my $this = shift;
        my $routine = shift;
        my @keys = @_;

	confess "$routine: no such routine"
		unless defined $this->{-routines}->{$routine};
        foreach my $key (@keys) {
                $this->{-bindings}->{$key} = $routine;
        }

        return $this;
}

sub process_bindings($;)
{
	my $this = shift;
	my $key = shift;
	
	# Find the binding to use.
	my $binding = $this->{-bindings}->{$key};
	if (not defined $binding) {
		# Check for default routine.
		$binding = $this->{-bindings}->{''}; 
	}
	
	if (defined $binding) {
		return $this->do_routine($binding, $key);
	} else {
		return $this;
	}
}

sub do_routine($;$)
{
	my $this = shift;
	my $binding = shift;
	my $key = shift; # TODO find out what $key was for :-)

	# Find the routine to call.
	my $routine = $this->{-routines}->{$binding};

	if (defined $routine) 
	{
		if (ref $routine eq 'CODE') {
			my $return = $routine->($this, $key);
			return $return;
		} else {
			return $routine;
		}
	} else {
		confess "No routine defined for "
			  . "keybinding \"$binding\"!";
	}
}

# ----------------------------------------------------------------------
# Generic focus 
# ----------------------------------------------------------------------

sub generic_focus($$;)
{
	my $this 	 	= shift;
	my $callback_time	= shift;
	my $control_keys 	= shift;
	my $cursor_visible 	= shift;
	my $pre_key_callback	= shift;

	$this->show;
	$this->run_event('-onfocus');

	$callback_time = 2 
		unless defined $callback_time;

	# The callback routine to call before a key
	# is grabbed (e.g. for layouting the screen).
	$pre_key_callback = sub {} 
		unless defined $pre_key_callback
		   and ref $pre_key_callback eq 'CODE';

	# A binding routine may return a scalar value
	# looking like: DO_KEY:<key>. The variable
	# $do_key will be set to <key>. If $do_key is
	# set at the point where normally a key would be
	# read, the key <key> is used instead.
	my $do_key;

	# Start the loop where keys are read.
        for (;;)
        {
		$pre_key_callback->($this);

		# Give focus to this widget and redraw it.
                $this->{-focus} = 1;
                $this->draw();

                # Grab a key or use the predefined key.
                my $key = defined $do_key 
		        ? $do_key
			: $this->get_key(
				$callback_time,
				$control_keys,
				$cursor_visible
			  );
		undef $do_key;

		# Do callback if needed.
                $this->process_callback;

		# Check if the screen resized.
		$this->root->check_for_resize;

		# No key pressed? Then retry grabbing one.
                next if $key eq '-1';

		# Process keybinding.
                my $return = $this->process_bindings($key);

		# If $return is something like DO_KEY:<...>, then
		# execute this key as if it was read from the
		# keyboard.
		if (defined $return and $return =~ /^DO_KEY\:(.*)$/)
		{
			$do_key = $1; 
			next;
		}
	
		# Return if keybinding returned a non-reference
		# value or a CODE reference. Else the next
		# key will be grabbed.
                elsif (not ref $return or ref $return eq 'CODE') 
		{
                        $this->{-focus} = 0;
                        $this->draw;
			$this->run_event('-onblur');
                        return (wantarray ? ($return, $key) : $return);
                } 
        }
}

# ----------------------------------------------------------------------
# Event handling
# ----------------------------------------------------------------------

sub clear_event($;)
{
	my $this = shift;
	my $event = shift;
	$this->set_event($event, undef);
	return $this;
}

sub set_event($;$)
{
	my $this      = shift;
	my $event     = shift;
	my $callback  = shift;

	if (defined $callback) 
	{
		if (ref $callback eq 'CODE') {
			$this->{$event} = $callback;
                } else {
                        confess "$event callback for $this "
                              . "($callback) is no CODE reference";
                }
	} else {
		$this->{$event} = undef;
	}
	return $this;
}

sub run_event($;)
{
	my $this = shift;
	my $event = shift;
	
	my $callback = $this->{$event};
	if (defined $callback) {
		if (ref $callback eq 'CODE') {
			return $callback->($this);
		} else {
			confess "$event callback for $this "
			      . "($callback) is no CODE reference";
		}
	}
	return;
} 

1;


=pod

=head1 NAME

Curses::UI::Widget - The base class for all widgets


=head1 CLASS HIERARCHY

 Curses::UI::Widget - base class



=head1 SYNOPSIS

This class is not used directly by somebody who is building an application
using Curses::UI. It's a base class that is expanded by the Curses::UI widgets.
See WIDGET STRUCTURE below for a basic widget framework.

    use Curses::UI::Widget;
    my $widget = new Curses::UI::Widget(
        -width  => 15,
        -height => 5,
        -border => 1,
    );




=head1 STANDARD OPTIONS

The standard options for (most) widgets are the options that are enabled
by this class. So this class doesn't really have standard options.





=head1 WIDGET-SPECIFIC OPTIONS

=head2 GENERAL:

=over 4

=item * B<-parent> < OBJECTREF >

This option specifies parent of the object. This parent is 
the object (Curses::UI, Window, Widget(descendant), etc.) 
in which the widget is drawn.

=item * B<-intellidraw> < BOOLEAN >

If BOOLEAN has a true value (which is the default), the
B<intellidraw> method (see below) will be suported. This
option is mainly used in widget building.

=item * B<-border> < BOOLEAN >

Each widget can be drawn with or without a border. To enable
the border use a true value and to disable it use a 
false value for BOOLEAN. The default is not to use a border.

=item * B<-sbborder> < BOOLEAN >

If no border is used, a square bracket border may be used.
This is a border which is constructed from '[' and ']' 
characters. This type of border is especially useful for 
single line widgets (like text entries and popup boxes).
A square bracket border can only be enabled if -border 
is false. The default is not to use a square bracket border.

=back



=head2 POSITIONING:
 
 +---------------------------------------------------+
 | parent                     ^                      |
 |                            |                      |
 |                            y                      |
 |                            |                      |
 |                            v                      |
 |                            ^                      |
 |                            |                      |
 |                          padtop                   |
 |                            |                      |
 |                            v                      |
 |                    +- TITLE -------+              |
 |                    | widget   ^    |              |
 |                    |          |    |              |
 |                    |          |    |              |
 |<--x--><--padleft-->|<----width---->|<--padright-->|
 |                    |          |    |              |
 |                    |          |    |              |
 |                    |        height |              |
 |                    |          v    |              |
 |                    +---------------+              |
 |                               ^                   |
 |                               |                   |
 |                           padbottom               |
 |                               |                   |
 |                               v                   |
 +---------------------------------------------------+


=over 4

=item * B<-x> < VALUE >             

The x-position of the widget, relative to the parent. The default
is 0.

=item * B<-y> < VALUE >

The y-position of the widget, relative to the parent. The default
is 0.

=item * B<-width> < VALUE >

The width of the widget. If the width is undefined or -1,
the maximum available width will be used. By default the widget
will use the maximum available width.

=item * B<-height> < VALUE >

The height of the widget. If the height is undefined or -1,
the maximum available height will be used. By default the widget
will use the maximum available height.

=back



=head2 PADDING:
 
=over 4

=item * B<-pad> < VALUE >

=item * B<-padtop> < VALUE >

=item * B<-padbottom> < VALUE >

=item * B<-padleft> < VALUE >

=item * B<-padright> < VALUE >

With -pad you can specify the default padding outside the widget
(the default value for -pad is 0). Using one of the -pad... options
that have a direction in them, you can override the default
padding.
 
=item * B<-ipad> < VALUE >

=item * B<-ipadtop> < VALUE >

=item * B<-ipadbottom> < VALUE >

=item * B<-ipadleft> < VALUE >

=item * B<-ipadright> < VALUE >

These are almost the same as the -pad... options, except these options
specify the padding _inside_ the widget. Normally the available 
effective drawing area for a widget will be the complete area
if no border is used or else the area within the border. 

=back



=head2 TITLE:

Remark:

A title is drawn in the border of a widget. So a title will only
be available if -border is true.

=over 4
 
=item * B<-title> < TEXT >

Set the title of the widget to TEXT. If the text is longer then the 
available width, it will be clipped.

=item * B<-titlereverse> < BOOLEAN >

The title can be drawn in normal or in reverse type. If -titlereverse
is true, the text will be drawn in reverse type. The default is to
use reverse type.

=item * B<-titlefullwidth> < BOOLEAN >

If -titlereverse is true, the title can be stretched to fill the
complete width of the widget by giving -titlefullwidth a true value.
By default this option is disabled.

=back

 

=head2 SCROLLBARS:

Remark: 

Since the user of a Curses::UI program has no real control over
the so called "scrollbars", they aren't really scrollbars. A 
better name would be something like "document loction indicators".
But since they look so much like scrollbars I decided I could get
away with this naming convention.
 
=over 4

=item * B<-vscrollbar> < VALUE >

VALUE can be 'left', 'right', another true value or false.

If -vscrollbar has a true value, a vertical scrollbar will
be drawn by the widget. If this true value happens to be "left",
the scrollbar will be drawn on the left side of the widget. In 
all other cases it will be drawn on the right side. The default
is not to draw a vertical scrollbar.

For widget programmers: To control the scrollbar, the widget
data -vscrolllen (the total length of the content of the widget)
and -vscrollpos (the current position in the document) should 
be set. If Curses::UI::Widget::draw is called, the scrollbar
will be drawn.

=item * B<-hscrollbar> < VALUE >

VALUE can be 'top', 'bottom', another true value or false.

If -hscrollbar has a true value, a horizontal scrollbar will
be drawn by the widget. If this true value happens to be "top",
the scrollbar will be drawn at the top of the widget. In 
all other cases it will be drawn at the bottom. The default
is not to draw a horizontal scrollbar.

For widget programmers: To control the scrollbar, the widget
data -hscrolllen (the maximum width of the content of the widget)
and -hscrollpos (the current horizontal position in the document) 
should be set. If Curses::UI::Widget::draw is called, 
the scrollbar will be drawn.

=back



=head2 EVENTS

=over 4

=item * B<-onfocus> < CODEREF >

This sets the onFocus event handler for the widget.
If the widget gets the focus, the code in CODEREF will 
be executed. It will get the widget reference as its 
argument.

=item * B<-onblur> < CODEREF >

This sets the onBlur event handler for the widget.
If the widget looses the focus, the code in CODEREF will 
be executed. It will get the widget reference as its 
argument.


=back


=head1 METHODS

=over 4

=item * B<new> ( OPTIONS )

Create a new Curses::UI::Widget instance using the options in HASH.

=item * B<layout> ( )

Layout the widget. Compute the size the widget needs and see
if it fits. Create the curses windows that are needed for
the widget (the border and the effective drawing area).

=item * B<draw> ( BOOLEAN )

Draw the Curses::UI::Widget. If BOOLEAN is true, the screen 
will not update after drawing. By default this argument is 
false, so the screen will update after drawing the widget.

=item * B<intellidraw> ( )

If the widget is visible (it is not hidden and it is in the
window that is currently on top) and if intellidraw is not
disabled for it (B<-intellidraw> has a true value) it is drawn 
and the curses routine doupdate() will be called to update 
the screen. 

This is useful if you change something in a widget and want 
it to update its state. If you simply call draw() and 
doupdate() yourself, then the widget will also be drawn if 
it is on a window that is currently not on top. This would 
result in the widget being drawn right through the contents 
of the window that is currently on top.

=item * B<focus> ( )

Give focus to the widget. In Curses::UI::Widget, this method
immediately returns, so the widget will not get focused. 
A derived class that needs focus, must override this method.

=item * B<title> ( TEXT )

Change the title that is shown in the border of the widget
to TEXT.

=item * B<width> ( )

=item * B<height> ( )

These methods return the total width and height of the widget.
This is the space that the widget itself uses plus the space that 
is used by the outside padding.

=item * B<borderwidth> ( )

=item * B<borderheight> ( )

These methods return the width and the height of the border of the
widget.

=item * B<screenwidth> ( )

=item * B<screenheight> ( )

These methods return the with and the height of the effective
drawing area of the widget. This is the area where the 
draw() method of a widget may draw the contents of the widget
(BTW: the curses window that is associated to this drawing
area is $this->{-windowscr}).

=item * B<width_by_windowscrwidth> ( NEEDWIDTH, OPTIONS )

=item * B<height_by_windowscrheight> ( NEEDHEIGHT, OPTIONS )

These methods are exported by this module. These can be used
in child classes to easily compute the total width/height the widget
needs in relation to the needed width/height of the effective drawing
area ($this->{-windowscr}). The OPTIONS contains the options that
will be used to create the widget. So if we want a widget that
has a drawing area height of 1 and that has a border, the -height
option can be computed using something like:

  my $height = height_by_windowscrheight(1, -border => 1); 

=item * B<generic_focus> ( BLOCKTIME, CTRLKEYS, CURSOR, PRECALLBACK )

For most widgets the B<generic_focus> method will be enough to 
handle focusing. This method will do the following:

It starts a loop for reading keyboard input from the user. 
At the start of this loop the PRECALLBACK is called. This callback
can for example be used for layouting the widget. Then, the widget 
is drawn. 

Now a key is read or if the DO_KEY:<key> construction was used,
the <key> will be used as if it was read from the keyboard (you
can find more on this construction below). If the DO_KEY:<key>
construction was not used, a key is read using the B<get_key>
method which is in L<Curses::UI::Common|Curses::UI::Common>. 
The arguments BLOCKTIME, CTRLKEYS and CURSOR are passed to 
B<get_key>.

Now the key is checked. If the value of the key is -1, B<get_key>
did not read a key at all. In that case, the program will go back
to the start of the loop.

As soon as a key is read, this key will be handed to the
B<process_bindings> method (see below). The returnvalue of this
method (called RETURN from now on) will be used to determine
what to do next. We have the following cases:

* B<RETURN matches DO_KEY:<key>>

The <key> is extracted from RETURN. The loop is restarted and
<key> will be used as if it was entered using the keyboard.

* B<RETURN is a CODE reference>

RETURN will be returned to the caller of B<generic_focus>. 
This will have the widget loose its focus. The caller then can 
execute the code.

* B<RETURN is a SCALAR value>

RETURN will be returned to the caller of B<generic_focus>. 
This will have the widget loose its focus. 

* B<anything else>

The widget will keep its focus. The loop will be restarted all 
over again. So, if you are writing a binding routine for a widget,
you can have the focus to stay at the widget by returning the 
widget instance itself. Example:

    sub myroutine() {
        my $this = shift;
        .... do your thing ....
        return $this;
    }


=item * B<process_bindings> ( KEY )

KEY -> maps via binding to -> ROUTINE -> maps to -> VALUE

This method will try to find out if there is a binding defined
for the KEY. If no binding is found, the method will return
the widget object itself.
If a binding is found, the method will check if there is
an corresponding ROUTINE. If the ROUTINE can be found it
will check if it's VALUE is a code reference. If it is, the
code will be executed and the returnvalue of this code will
be returned. Else the VALUE will directly be returned.

=item * B<clear_binding> ( ROUTINE )

Clear all keybindings for routine ROUTINE. 

=item * B<set_routine> ( ROUTINE, VALUE )

Set the routine ROUTINE to the VALUE. The VALUE may either be a 
scalar value or a code reference. If B<process_bindings> (see above)
sees a scalar value, it will return this value. If it sees a
coderef, it will execute the code and return the returnvalue of
this code. 

=item * B<set_binding> ( ROUTINE, KEYLIST )

Bind the keys in the list KEYLIST to the ROUTINE. If you use an
empty string for a key, then this routine will become the default
routine (in case no other keybinding could be found). This 
is for example used in the TextEditor widget.

=item * B<set_event> ( EVENT, [CODEREF] )

This routine will set the callback for event EVENT to
CODEREF. If CODEREF is omitted or undefined, the event will 
be cleared.

=item * B<clear_event> ( EVENT )

This will clear the callback for event EVENT.

=item * B<run_event> ( EVENT )

This routine will check if a callback for the event EVENT
is set and if is a code reference. If this is the case, 
it will run the code and return its return value. 

=item * B<onFocus> ( CODEREF )

This method can be used to set the B<-onfocus> event handler
(see above) after initialization of the widget. 

=item * B<onBlur> ( CODEREF )

This method can be used to set the B<-onblur> event handler
(see above) after initialization of the widget. 

=item * B<parentwindow> ( )

Returns this parent window for the widget or undef if
no parent window can be found (this should not happen).

=item * B<in_topwindow> ( )

Returns true if the widget is in the window that is 
currently on top.

=back




=head1 WIDGET STRUCTURE

Here's a basic framework for creating a new widget. You do not have
to follow this framework. As long as your widget has the methods
new(), layout(), draw() and focus(), it can be used in Curses::UI.

    package Curses::UI::YourWidget
    
    use Curses;
    use Curses::UI::Widget;  
    use Curses::UI::Common; # some common widget routines

    use vars qw($VERSION @ISA);
    $VERSION = '1.0.0';
    @ISA = qw(Curses::UI::Widget Curses::UI::Common);

    # For a widget that can get focus, you should define
    # the routines that are used to control the widget.
    # Each routine has a name. This name is used in 
    # the definition of the bindings. 
    # The value can be a string or a subroutine reference. 
    # A string will make the widget return from focus.
    #
    my %routines = (
        'return'    => 'RETURN',
        'key-a'     => \&key_a,
        'key-other' => \&other_key
    );

    # Using the bindings, the routines can be binded to key-
    # presses. If the keypress is an empty string, this means
    # that this is the default binding. If the key is not 
    # handled by any other binding, it's handled by this
    # default binding.
    #
    my %bindings = (
        KEY_DOWN()  => 'return',   # down arrow will make the 
                                   # widget loose it's focus
        'a'         => 'key-a',    # a-key will trigger key_a()
        ''          => 'key-other' # any other key will trigger other_key()
    );

    # The creation of the widget. When doing it this way,
    # it's easy to make optional and forced arguments 
    # possible. A forced argument could for example be 
    # -border => 1, which would mean that the widget
    # always has a border, which can't be disabled by the
    # programmer. The arguments can of course be used 
    # for storing the current state of the widget.
    #
    sub new () {
        my $class = shift;
        my %args = (
            -optional_argument_1 => "default value 1",
            -optional_argument_2 => "default value 2",
            ....etc....
            @_,
            -forced_argument_1   => "forced value 1", 
            -forced_argument_2   => "forced value 2", 
            ....etc....
            -bindings            => {%bindings},
            -routines            => {%routines},
        );

        # Create the widget and do the layout of it.
        my $this = $class->SUPER::new( %args );
	$this->layout;

	return $this;
    }

    # Each widget should have a layout() routine. Here,
    # the widget itself and it's contents can be layouted.
    # In case of a very simple widget, this will only mean
    # that the Widget has to be layouted (in which case the
    # routine could be left out, since it's in the base
    # class already). In other cases you will have to add
    # your own layout code. This routine is very important,
    # since it will enable the resizeability of the widget!
    #
    sub layout () {
        my $this = shift;

        $this->SUPER::layout;
	return $this if $Curses::UI::screen_too_small;

        ....your own layout stuff....

        # If you decide that the widget does not fit on the
        # screen, then set $Curses::UI::screen_too_small
        # to a true value and return.	
        if ( ....the widget does not fit.... ) {
            $Curses::UI::screen_too_small++;
            return $this;
        }

        return $this;
    }

    # The widget is drawn by the draw() routine. The
    # $no_update part is used to disable screen flickering
    # if a lot of widgets have to be drawn at once (for
    # example on resizing or redrawing). The curses window
    # which you can use for drawing the widget's contents
    # is $this->{-windowscr}.
    #
    sub draw(;$) {
        my $this = shift;
        my $no_doupdate = shift || 0;
        return $this if $this->hidden;
        $this->SUPER::draw(1);

        ....your own draw stuff....
        $this->{-windowscr}->addstr(0, 0, "Fixed string");
        ....your own draw stuff....

        $this->{-windowscr}->noutrefresh;
        doupdate() unless $no_doupdate;
	return $this;
    }

    # Focus the widget. If you do not override this routine
    # from Curses::UI::Widget, the widget will not be 
    # focusable. Mostly you will use the generic_focus() method.
    #
    sub focus()
    {
        my $this = shift;
        $this->show; # makes the widget visible if it was invisible
        return $this->generic_focus(
            undef,             # delaytime, default = 2 (1/10 second).
            NO_CONTROLKEYS,    # disable controlkeys like CTRL+C. To enable
                               # them use CONTROLKEYS instead.
            CURSOR_INVISIBLE,  # do not show the cursor (if supported). To
                               # show the cursor use CURSOR_VISIBLE.
            \&pre_key_routine, # optional callback routine to execute
                               # before a key is read. Mostly unused.
        );
    }  
    
    ....your own widget handling routines....




=head1 SEE ALSO

L<Curses::UI|Curses::UI>






=head1 AUTHOR

Copyright (c) 2001-2002 Maurice Makaay. All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty. It may be used, redistributed and/or modified
under the same terms as perl itself.

