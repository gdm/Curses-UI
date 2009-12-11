package Curses::UI::FileBrowser;

use strict;
use Carp qw(confess);
use Curses;
use Curses::UI::Window;
use Curses::UI::Common;

use vars qw($VERSION @ISA);
@ISA = qw(Curses::UI::Window Curses::UI::Common);
$VERSION = '1.0.0';

sub new ()
{
	my $class = shift;
	my %args = ( 
		-title 		=> 'Select file',
		-path		=> '/',	
		-file		=> '', 
		-mask_values 	=> undef,
		-mask_labels 	=> undef,
		-mask_selected 	=> 0,
		-edit_filename 	=> 0,
		@_,
		-border 	 => 1,
		-titleinverse 	 => 0,
		-ipad		 => 1,
		-selected_cache  => {},
	);

	my $this = $class->SUPER::new(%args);
	$this->layout();

	my $buttons = $this->add('buttons', 'Curses::UI::Buttons',
		-y 		 => -1,
		-x		 => 0,
		-width 		 => undef, 
		-buttonalignment => 'right',
		-mayloosefocus 	 => 1,
		-buttons 	 => ['< OK >', '< Cancel >'],
		-values 	 => [1, 0],
	);
	$buttons->set_routine('return', \&return);

	my $dirbrowser = $this->add('dirbrowser', 'Curses::UI::ListBox',
		-y 		 => 0,
		-border 	 => 1,
		-width 		 => int(($this->screenwidth - 3)/2),
		-padbottom 	 => 6,
		-values 	 => [],
		-vscrollbar 	 => 1,
		-labels		 => { '..' => '.. (One directory up)' } 
	);	
	$dirbrowser->set_routine('option-select',\&dirselect);
	
	my $filebrowser = $this->add('filebrowser', 'Curses::UI::ListBox',
		-y 		 => 0,
		-x 		 => $this->getobj('dirbrowser')->width + 1,
		-border 	 => 1,
		-padbottom 	 => 6,
		-vscrollbar 	 => 1,
		-values 	 => ["info.txt","passwd"],
	);	
	$filebrowser->set_routine('option-select', \&fileselect);

	my $labeloffset = 1;
	my $textoffset = 7;

	$this->add('pathlabel', 'Curses::UI::Label',
		-x 		 => $labeloffset, 
		-y 		 => $this->screenheight - 5, 
		-text		 => 'Path:',
	);
	$this->add('pathvalue', 'Curses::UI::Label',
		-x 		 => $textoffset,
		-y 		 => $this->screenheight - 5, 
		-width		 => $this->screenwidth - 6,
		-text		 => $this->{-path},
	);

	$this->add('filelabel', 'Curses::UI::Label',
		-x 		 => $labeloffset, 
		-y 		 => $this->screenheight - 4, 
		-text		 => 'File:',
	);
	
	if ($this->{-editfilename})
	{
		$this->add('filevalue', 'Curses::UI::TextEntry',
			-x		 => $textoffset,
			-y 		 => $this->screenheight - 4, 
			-text		 => $this->{-file},
			-width		 => 32,
			-showlines	 => 1,
			-border		 => 0,
			-sbborder	 => 0,
			-regexp		 => '/^[^\/]*$/',
		);
	} else {
		$this->add('filevalue', 'Curses::UI::Label',
			-x 		 => $textoffset, 
			-y 		 => $this->screenheight - 4, 
			-text		 => $this->{-file},
			-width		 => $this->screenwidth - 6,
		);
	}

	if (defined $this->{-mask_values}) 
	{
		$this->add('masklabel', 'Curses::UI::Label',
			-x 	 => $labeloffset,
			-y 	 => $this->screenheight - 2,
			-text 	 => 'Mask:',
		);
		my $maskbox = $this->add('maskbox', 'Curses::UI::PopupBox',
			-x 	 => $textoffset,
			-y 	 => $this->screenheight - 2,
			-values  => $this->{-mask_values},
			-labels  => $this->{-mask_labels},
			-selected => $this->{-mask_selected},
		);
		$this->{-mask} = $maskbox->get;
		$maskbox->set_routine('option-select', \&maskbox_select);
		$maskbox->set_routine('select-next',   \&maskbox_next);
		$maskbox->set_routine('select-prev',   \&maskbox_prev);
	}

	$this->returnkeys(KEY_ESCAPE);

	$this->layout();
	$this->get_dir;
	return bless $this, $class;
}

sub layout()
{
	my $this = shift;

	my $w = 60;
	my $h = 18;
	$h += 2 if defined $this->{-mask_values};

	# Compute the coordinates for the widget.
	my $x = int(($ENV{COLS} - $w) / 2);
	my $y = int(($ENV{LINES} - $h) / 2);
	$x = 0 if $x < 0;
	$y = 0 if $y < 0;

	$this->{-x} = $x;
	$this->{-y} = $y;
	$this->{-width} = $w,
	$this->{-height} = $h,
	$this->SUPER::layout();

	return $this;
}

sub get_dir()
{
	my $this = shift;

	# Get pathvalue, filevalue, dirbrowser and filebrowser objects.
	my $pv = $this->getobj('pathvalue');
	my $db = $this->getobj('dirbrowser');
	my $fb = $this->getobj('filebrowser');

	my $path = $pv->text;

	# Resolve path.
	$path =~ s|/+|/|g;
	my @path = split /\//, $path;
	my @resolved = ();
	foreach my $dir (@path)
	{
		if ($dir eq '.') { next }
		elsif ($dir eq '..') { pop @resolved if @resolved }
		else { push @resolved, $dir }
	}
	$path = join "/", @resolved;
	
	# Catch totally bogus paths.
	if (not -d $path) { $path = "/" }
	
	$pv->text($path);
	
	my @dirs = ();
	my @files = ();
	unless (opendir D, $path)
	{
		my $error = "Can't open the directory\n"
		          . "$path\nError: $!";
		return $this->root->error(-message => $error);
	}
	foreach my $f (sort readdir D)
	{
		next if $f =~ /^.$|^..$/;
		push @dirs,  $f if -d "$path/$f";
		if (-f "$path/$f")
		{
			$this->{-mask} = '.' unless defined $this->{-mask};
			push @files, $f if $f =~ /$this->{-mask}/i;
		}
	}
	closedir D;

	unshift @dirs, ".." if $path ne '/';
	
	$db->{-values} = \@dirs;
	$db->{-ypos} = $this->{-selected_cache}->{$path};
	$db->{-ypos} = 0 unless defined $db->{-ypos};
	$db->{-selected} = undef;
	$db->layout_content->draw;

	$fb->{-values} = \@files;
	$fb->{-ypos} = $fb->{-yscrpos} = 0;
	$fb->layout_content->draw;
	
	return $this;
}

sub dirselect()
{
	my $db = shift; # dirbrowser
	my $this = $db->parent;
	my $fv = $this->getobj('filevalue');
	my $dv = $this->getobj('pathvalue');

	my $add = $db->{-values}->[$db->{-ypos}];
	my $savepath = $dv->text;
	$this->{-selected_cache}->{$savepath} = $db->{-ypos};
	$dv->text("/$savepath/$add");
	$fv->text('');
	unless ($this->get_dir) {
		$dv->text($savepath);
	}

	return $db;
}

sub fileselect()
{
	my $filebrowser = shift;
	my $this = $filebrowser->parent;

	my $file = $filebrowser->{-values}->[$filebrowser->{-ypos}];
	$this->{-file} = $file;
	$this->getobj('filevalue')->text("$file");
	
	$this->focus_to_object('buttons');
	return 'STAY_AT_FOCUSPOSITION';
}

sub maskbox_select()
{
	my $popup = shift;

	# first parent is the PopupBox
	my $this = $popup->parent->parent; 

	$popup->option_select;
	$this->{-mask} = $popup->get;
	$this->get_dir;
	return;
}

sub maskbox_prev()
{
	my $maskbox = shift; 
	my $this = $maskbox->parent;
	$maskbox->select_prev;
	$this->{-mask} = $maskbox->get;
	$this->get_dir;
	return $maskbox;	
}
sub maskbox_next()
{
	my $maskbox = shift; 
	my $this = $maskbox->parent;
	$maskbox->select_next;
	$this->{-mask} = $maskbox->get;
	$this->get_dir;
	return $maskbox;	
}

sub draw(;$)
{
	my $this = shift;
	my $no_doupdate = shift || 0;

        # Return immediately if this object is hidden.
        return $this if $this->hidden;
	
	# Draw Window
	$this->SUPER::draw(1);

	$this->{-windowscr}->noutrefresh();
	doupdate() unless $no_doupdate;

	return $this;
}

sub get()
{
	my $this = shift;
	if ($this->getobj('buttons')->get) {
		my $file = $this->getobj('pathvalue')->get
			 . "/" 
			 . $this->getobj('filevalue')->get;
		$file =~ s|/+|/|g;
		return $file;
	} else {
		return;
	}
}

sub focus()
{
	my $this = shift;
	$this->show;
	$this->SUPER::draw;
	$this->focus_to_object($this->{-file} ne ''?'buttons':'dirbrowser');
	my ($return, $key) = $this->SUPER::focus;
	
	# Escape pressed? Then select the cancel button.
	if ($key eq KEY_ESCAPE) {
		$this->getobj('buttons')->{-selected} = 1;
	}

	return $this;
}

sub return()
{
	my $buttons = shift;	
	my $this = $buttons->parent();
	my $file = $this->get;
	my $ok_pressed = $this->getobj('buttons')->get;
	if ($ok_pressed and $file =~ m|/$|)
	{
		$this->root->error(-message => "You have not yet selected a file!");
		return 'STAY_AT_FOCUSPOSITION';
	} else {
		return 'LEAVE_CONTAINER';
	}
}


1;
