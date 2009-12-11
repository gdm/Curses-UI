# ----------------------------------------------------------------------
# Curses::UI
#
# (c) 2001-2002 by Maurice Makaay. All rights reserved.
# This file is part of Curses::UI. Curses::UI is free software.
# You can redistribute it and/or modify it under the same terms
# as perl itself.
#
# Currently maintained by Marcus Thiesen
# e-mail: marcus@cpan.thiesenweb.de
# ----------------------------------------------------------------------

package Curses::UI;

# If we do not know a terminal type, then imply VT100.
BEGIN { $ENV{TERM} = 'vt100' unless defined $ENV{TERM} }

use Curses;
use Curses::UI::Container;
use Curses::UI::Common;
use Curses::UI::Language;
use FileHandle;
use Term::ReadKey;
require Exporter;

use vars qw(
    $VERSION 
    @ISA
    @EXPORT
);

$VERSION = "0.73";

@EXPORT = qw(
    MainLoop
);

@ISA = qw(
    Curses::UI::Container 
    Curses::UI::Common
);

$Curses::UI::rootobject       = undef;
$Curses::UI::debug            = 0; 
$Curses::UI::screen_too_small = 0; 
$Curses::UI::initialized      = 0;

# Detect ncurses functionality. Magic for Solaris 8
eval { $Curses::UI::ncurses_mouse    = (Curses->can('NCURSES_MOUSE_VERSION') and
                                 (NCURSES_MOUSE_VERSION() >= 1 ) ) };

# ----------------------------------------------------------------------
# Constructor
# ----------------------------------------------------------------------

sub new()
{
    my $class = shift;

    my %userargs = @_;
    keys_to_lowercase(\%userargs);

    my %args = (
        -compat        => 0,     # Use compatibility mode?
        -clear_on_exit => 0,     # Clear screen if program exits?
        -cursor_mode   => 0,     # What is the current cursor_mode?
	-debug         => undef, # Turn on debugging mode?
	-language      => undef, # Which language to use?
	-mouse_support => 1,     # Do we want mouse support

        #user data
        -userdata       => undef,    #user internal data
 
        %userargs,

	-read_timeout  => -1,    # full blocking read by default
    );

    $Curses::UI::debug = $args{-debug} 
        if defined $args{-debug};

    $Curses::UI::ncurses_mouse = $args{-mouse_support}
        if defined $args{-mouse_support};

    $Curses::UI::rootobject->fatalerror(
        "You can only initiate one Curses::UI rootobject!\n"
    ) if defined $Curses::UI::rootobject;

    my $this = bless { %args }, $class;
    $Curses::UI::rootobject = $this;

    my $lang = new Curses::UI::Language($this->{-language});
    $this->lang($lang);
    print STDERR "DEBUG: Loaded language: $lang->{-lang}\n"
	if $Curses::UI::debug;

    $this->layout();    

    return $this;
}

# ----------------------------------------------------------------------
# Destructor
# ----------------------------------------------------------------------

DESTROY 
{ 
    my $this = shift;
    endwin();
    $Curses::UI::rootobject = undef;

    if ($this->{-clear_on_exit})
    {
        my $save_path = $ENV{PATH};
        $ENV{PATH} = "/bin:/usr/bin";
        system "clear";
        $ENV{PATH} = $save_path;
    }
}

# ----------------------------------------------------------------------
# Accessor functions
# ----------------------------------------------------------------------

sub compat(;$)        { shift()->accessor('-compat',          shift()) }
sub clear_on_exit(;$) { shift()->accessor('-clear_on_exit',   shift()) }
sub cursor_mode(;$)   { shift()->accessor('-cursor_mode',     shift()) }
sub lang(;$)          { shift()->accessor('-language_object', shift()) }

# TODO: document
sub debug(;$)         
{ 
    my $this  = shift;
    my $value = shift;
    $Curses::UI::debug = $this->accessor('-debug', $value);
}

# ----------------------------------------------------------------------
# Window resizing support
# ----------------------------------------------------------------------

sub layout()
{
    my $this = shift;

    return $this if $Curses::UI::initialized;

    $Curses::UI::screen_too_small = 0;

    # Initialize the curses screen.
    initscr();
    noecho();
    raw();

    # Mouse events if possible
    my $old = 0;
    if ( $Curses::UI::ncurses_mouse ) 
    {
	print STDERR "DEBUG: ncurses mouse events are enabled\n"
	    if $Curses::UI::debug;
        # In case of gpm, mousemask fails. 
	eval { mousemask( ALL_MOUSE_EVENTS(), $old ) };
        print STDERR "mousemask() failed: $@\n" if $@;
    }   
	
    # find the terminal size.
    my ($cols,$lines) = GetTerminalSize;
    $ENV{COLS}  = $cols;
    $ENV{LINES} = $lines;

    # Create root window.
    my $root = newwin($lines, $cols, 0, 0);
    die "newwin($lines, $cols, 0, 0) failed\n"
	unless defined $root;

    # Let this object present itself as a standard 
    # Curses::UI widget, regarding size, location and
    # drawing area. This will make it possible for
    # child windows / widgets to layout and draw themselves.
    #    
    $this->{-width}  = $this->{-w} = $this->{-bw} = $cols;
    $this->{-height} = $this->{-h} = $this->{-bh} = $lines;
    $this->{-x}      = $this->{-y} = 0;
    $this->{-canvasscr} = $root;

    # Walk through all contained objects and let them 
    # layout themselves.
    $this->layout_contained_objects;
    
    $Curses::UI::initialized = 1;
    
    return $this;    
}

# ----------------------------------------------------------------------
# Event handling
# ----------------------------------------------------------------------

# Tk-like mainloop, just for fun :-)
sub MainLoop ()
{
    die "No Curses::UI rootobject available!\n"
        unless defined $Curses::UI::rootobject;
    $Curses::UI::rootobject->mainloop;
}

sub mainloop ()
{
    my $this = shift;

    # Draw the initial screen.
    $this->focus(undef, 1); # 1 = forced focus
    $this->draw;
    doupdate();

    # Inifinite event loop.
    for(;;) 
    { 
        $this->do_one_event 
    }
}

# TODO: document
sub do_one_event(;$)
{
    my $this = shift;
    my $object = shift;
    $object = $this unless defined $object;
        
    eval {curs_set($this->{-cursor_mode})};

    # Read a key or use the feeded key.
    my $key = $this->{-feedkey};
    unless (defined $key) {
        $key = $this->get_key($this->{-read_timeout});
    }
    $this->{-feedkey} = undef;

    # ncurses sends KEY_RESIZE() key on resize. Ignore this key.
    if (Curses->can("KEY_RESIZE")) {
        $key = '-1' if $key eq KEY_RESIZE();
    }

    # ncurses sends KEY_MOUSE()
    if ($Curses::UI::ncurses_mouse) {
	if ($key eq KEY_MOUSE()) {
	    $this->handle_mouse_event($object);
	    doupdate();
	    return $this;
	}
    }

    # If the screen is too small, then <CTRL+C> will exit.
    # Else the next event loop will be started.
    if ($Curses::UI::screen_too_small) {
	exit(1) if $key eq "\cC";
	return $this;
    }

    # Delegate the keypress. This is not done to $this,
    # but to $object, so all events will go to the 
    # object that called do_one_event(). This is used to
    # enable modal focusing. 
    #
    $object->event_keypress($key) unless $key eq '-1';
        
    # Execute timer code.
    $this->do_timer;

    # See if there are pending keys on input. If I do not
    # feed them to the application in this way, the screen
    # hangs in case I do a lot of input on my Solaris
    # machine.
    $key = $this->get_key(0);
    $this->feedkey($key) unless $key eq '-1';

    # Update the screen.
    doupdate();

    return $this;
}

sub draw()
{
    my $this = shift;
    my $no_doupdate = shift || 0;

    if ($Curses::UI::screen_too_small) 
    {
        my $s = $this->{-canvasscr};
        $s->clear;
        $s->addstr(0, 0, $this->lang->get('screen_too_small'));
        $s->move(4,0);
        $s->noutrefresh();
	doupdate();
    } else {
	$this->SUPER::draw(1);
	doupdate() unless $no_doupdate;
    }
}

# TODO: document
sub feedkey()
{
    my $this = shift;
    my $key = shift;
    $this->flushkeys();
    $this->{-feedkey} = $key;
    return $this;
}

# TODO: document
sub flushkeys()
{
    my $this = shift;
    
    my $key = '';
    my @k = ();
    until ( $key eq "-1" ) {
        $key = $this->get_key(0);
    }
}


# ----------------------------------------------------------------------
# Timed event handling
# ----------------------------------------------------------------------

sub set_read_timeout()
{
    my $this = shift;

    my $new_timeout = -1;
    TIMER: while (my ($id, $config) = each %{$this->{-timers}}) 
    {
        # Skip timer if it is disabled.
        next TIMER unless $config->{-enabled};

	$new_timeout = $config->{-time} 
	    unless $new_timeout != -1 and
	           $new_timeout < $config->{-time};
    }
    $new_timeout = 1 if $new_timeout < 0 and $new_timeout != -1;

    $this->{-read_timeout} = $new_timeout;
    return $this;
}

sub set_timer($$;)
{
    my $this     = shift;
    my $id       = shift;
    my $callback = shift;
    my $time     = shift || 1;

    $this->fatalerror(
        "add_timer(): callback is no CODE reference"
    ) unless defined $callback and ref $callback eq 'CODE';

    $this->fatalerror(
	"add_timer(): id is not set"
    ) unless defined $id;

    my $config = {
        -time     => int($time),
        -callback => $callback,
        -enabled  => 1,
        -lastrun  => time(),
    };
    $this->{-timers}->{$id} = $config;

    $this->set_read_timeout;

    return $this;
}

sub disable_timer($;)
{
    my ($this,$id) = @_;
    if (defined $this->{-timers}->{$id}) {
        $this->{-timers}->{$id}->{-enabled} = 0;
    }    
    $this->set_read_timeout;
    return $this;
}

sub enable_timer($;)
{
    my ($this,$id) = @_;
    if (defined $this->{-timers}->{$id}) {
        $this->{-timers}->{$id}->{-enabled} = 1;
    }    
    $this->set_read_timeout;
    return $this;
}

sub delete_timer($;)
{
    my ($this,$id) = @_;
    if (defined $this->{-timers}->{$id}) {
        delete $this->{-timers}->{$id};
    }    
    $this->set_read_timeout;
    return $this;
}

sub do_timer()
{
    my $this = shift;

    my $now = time();
    my $timers_done = 0;

    TIMER: while (my ($id, $config) = each %{$this->{-timers}}) 
    {
        # Skip timer if it is disabled.
        next TIMER unless $config->{-enabled};

        # No -lastrun set? Then do it now.
        unless (defined $config->{-lastrun})
        {
            $config->{-lastrun} = $now; 
            next TIMER;
        }

        if ($config->{-lastrun} <= ($now - $config->{-time})) 
        { 
            $config->{-callback}->($this);
            $config->{-lastrun} = $now;
            $timers_done++;
        }
    }

    # Bring the cursor back to the focused object by
    # redrawing it. Due to drawing other objects, it might 
    # have moved to another widget or screen location.
    #
    $this->focus_path(-1)->draw if $timers_done;
        
    return $this;
}

# ----------------------------------------------------------------------
# Mouse events
# ----------------------------------------------------------------------

sub handle_mouse_event()
{
    my $this = shift;
    my $object = shift;
    $object = $this unless defined $object;

    my $MEVENT = 0;
    getmouse($MEVENT);

    # $MEVENT is a struct. From curses.h (note: this might change!):
    #
    # typedef struct
    # {
    #    short id;           /* ID to distinguish multiple devices */
    #	 int x, y, z;        /* event coordinates (character-cell) */
    #	 mmask_t bstate;     /* button state bits */
    # } MEVENT;
    #
    # ---------------
    # s signed short
    # x null byte
    # x null byte
    # ---------------
    # i integer
    # ---------------
    # i integer
    # ---------------
    # i integer
    # ---------------
    # l long
    # ---------------

    my ($id, $x, $y, $z, $bstate) = unpack("sx2i3l", $MEVENT);
    my %MEVENT = (
	-id     => $id,
	-x      => $x,
	-y      => $y,
	-bstate => $bstate
    );

    # Get the objects at the mouse event position.
    my $tree = $this->object_at_xy($object, $MEVENT{-x}, $MEVENT{-y});
   
    # Walk through the object tree, top object first.
    foreach my $object (reverse @$tree)
    {
	# Send the mouse-event to the object. 
	# Leave the loop if the object handled the event.
	my $return = $object->event_mouse(\%MEVENT);
	last if defined $return and $return ne 'DELEGATE';
    }
}

sub object_at_xy($$;$)
{
    my $this = shift;
    my $object = shift;
    my $x = shift;
    my $y = shift;
    my $tree = shift;
    $tree = [] unless defined $tree;

    push @$tree, $object;

    my $idx = -1;
    while (defined $object->{-draworder}->[$idx])
    {
        my $testobj = $object->getobj($object->{-draworder}->[$idx]);
        $idx--;

        # Find the window parameters for the $testobj.
        my $scr = defined $testobj->{-borderscr} ? '-borderscr' : '-canvasscr';
        my $winp = $testobj->windowparameters($scr);

        # Does the click fall inside this object?
        if ( $x >= $winp->{-x} and
             $x <  ($winp->{-x}+$winp->{-w}) and
             $y >= $winp->{-y} and
             $y <  ($winp->{-y}+$winp->{-h}) ) {

            if ( $testobj->isa('Curses::UI::Container') and
                 not $testobj->isa('Curses::UI::ContainerWidget')) {
                $this->object_at_xy($testobj, $x, $y, $tree)
            } else {
                push @$tree, $testobj;
            }
            return $tree;
        }
    }

    return $tree;
}


# ----------------------------------------------------------------------
# Other subroutines
# ----------------------------------------------------------------------

# TODO: document
sub fatalerror($$;$)
{
    my $this  = shift;
    my $error = shift;
    my $exit  = shift;

    $exit = 1 unless defined $exit;
    chomp $error; 
    $error .= "\n";

    my $s = $this->{-canvasscr};
    $s->clear;
    $s->addstr(0,0,"Fatal program error:\n"
    	     . "-"x($ENV{COLS}-1) . "\n"
    	     . $error 
    	     . "-"x($ENV{COLS}-1) . "\n"
    	     . "Press any key to exit...");
    $s->noutrefresh();
    doupdate();

    $this->flushkeys();
    for (;;) 
    {
	$key = $this->get_key();
	last if $key ne "-1";
    } 

    exit($exit);
}

sub usemodule($;)
{
    my $this = shift;
    my $class = shift;

    # Create class filename.
    my $file = $class;
    $file =~ s|::|/|g; 
    $file .= '.pm';

    # Automatically load the required class.
    if (not defined $INC{$file})
    {
        eval 
	{
            require $file;
            $class->import;
        };

        # Fatal error if the class could not be loaded.
	$this->fatalerror("Could not load $class from $file:\n$@")
	    if $@;
    }

    return $this;
}

sub focus_path()
{
    my $this = shift;
    my $index = shift;

    my $p_obj = $this;
    my @path = ($p_obj);
    for(;;)
    {
        my $p_el = $p_obj->{-draworder}->[-1];
        last unless defined $p_el;
        $p_obj = $p_obj->{-id2object}->{$p_el};
        push @path, $p_obj;
        last if $p_obj->isa('Curses::UI::ContainerWidget');
    }

    return (defined $index ? $path[$index] : @path);
}

# add() is overridden, because we only want to be able
# to add Curses::UI:Window objects to the Curses::UI
# rootlevel.
#
sub add()
{
    my $this = shift;
    my $id = shift;
    my $class = shift;
    my %args = @_;
    
    # Make it possible to specify WidgetType instead of
    # Curses::UI::WidgetType.
    $class = "Curses::UI::$class" 
        if $class !~ /\:\:/ or 
           $class =~ /^Dialog\:\:[^\:]+$/;

    $this->usemodule($class);

    $this->fatalerror(
	    "You may only add Curses::UI::Window objects to "
          . "Curses::UI and no $class objects"
    ) unless $class->isa('Curses::UI::Window');

    $this->SUPER::add($id, $class, %args);
}

# Sets/Get the user data
sub userdata
{
    my $this = shift;
    if (defined $_[0])
    {
        $this->{-userdata} = $_[0];
    }
    return $this->{-userdata};
}

# ----------------------------------------------------------------------
# Focusable dialog windows
# ----------------------------------------------------------------------

sub tempdialog()
{
    my $this = shift;
    my $class = shift;
    my %args = @_;

    my $id = "__window_$class";

    my $dialog = $this->add($id, $class, %args);
    $dialog->modalfocus;
    $return = $dialog->get;
    $this->delete($id);
    $this->root->focus(undef, 1);
    return $return;
}

# The argument list will be returned unchanged, unless it
# contains only one item. In that case ($ifone, $_[0]) will
# be returned. This enables constructions like:
#
#    $cui->dialog("Some dialog message");
#
# instead of:
#
#    $cui->dialog(-message => "Some dialog message");
#
sub process_args($$;)
{
    my $this = shift;        
    my $ifone = shift;
    if (@_ == 1) { @_ = ($ifone => $_[0]) }
    return @_;
}

sub error()
{
    my $this = shift;
    my %args = $this->process_args('-message', @_);
    $this->tempdialog('Dialog::Error', %args);
}

sub dialog()
{
    my $this = shift;
    my %args = $this->process_args('-message', @_);
    $this->tempdialog('Dialog::Basic', %args);
}

sub calendardialog()
{
    my $this = shift;
    my %args = $this->process_args('-title', @_);
    $this->tempdialog('Dialog::Calendar', %args);
}

sub filebrowser()
{
    my $this = shift;
    my %args = $this->process_args('-title', @_);

    # Create title
    unless (defined $args{-title}) {
	my $l = $this->root->lang;
	$args{-title} = $l->get('file_title');
    }

    # Select a file to load from.
    $this->tempdialog('Dialog::Filebrowser', %args);
}

sub savefilebrowser()
{
    my $this = shift;
    my %args = $this->process_args('-title', @_);
    
    my $l = $this->root->lang;

    # Create title.
    $args{-title} = $l->get('file_savetitle')
	unless defined $args{-title};
    
    # Select a file to save to.
    my $file = $this->filebrowser(-editfilename => 1, %args);
    return unless defined $file;
    
    # Check if the file exists. Ask for overwrite
    # permission if it does.
    if (-e $file)
    {
	# Get language specific data.
	my $pre = $l->get('file_overwrite_question_pre');
	my $post = $l->get('file_overwrite_question_post');
	my $title = $l->get('file_overwrite_title');

        my $overwrite = $this->dialog(
            -title     => $title,
            -buttons   => [ 'yes', 'no' ],
            -message   => $pre . $file . $post,
        );
        return unless $overwrite;
    }
    
    return $file;
}

sub loadfilebrowser()
{
    my $this = shift;
    my %args = $this->process_args('-title', @_);

    # Create title
    unless (defined $args{-title}) {
	my $l = $this->root->lang;
	$args{-title} = $l->get('file_loadtitle');
    }

    $this->filebrowser(-editfilename  => 0, %args);
}

# ----------------------------------------------------------------------
# Non-focusable dialogs
# ----------------------------------------------------------------------

my $status_id = "__status_dialog";
sub status($;)
{
    my $this = shift;
    my %args = $this->process_args('-message', @_);

    $this->delete($status_id);
    $this->add($status_id, 'Dialog::Status', %args)->draw;
    
    return $this;    
}

sub nostatus()
{
    my $this = shift;
    $this->delete($status_id);
    $this->flushkeys();
    $this->draw;
    return $this;
}

sub progress()
{
    my $this = shift;
    my %args = @_;

    $this->add(
        "__progress_$this",
        'Dialog::Progress', 
        %args
    );
    $this->draw;

    return $this;
}

sub setprogress($;$)
{
    my $this = shift;
    my $pos  = shift;
    my $message = shift;

    # If I do not do this, the progress bar seems frozen
    # if a key is pressed on my Solaris machine. Flushing
    # the input keys solves this. And this is not a bad
    # thing to do during a progress dialog (input is ignored
    # this way).
    $this->flushkeys;

    my $p = $this->getobj("__progress_$this");
    return unless defined $p;
    $p->pos($pos) if defined $pos;
    $p->message($message) if defined $message;
    $p->draw;

    return $this;
}

sub noprogress()
{
    my $this = shift;
    $this->delete("__progress_$this");
    $this->flushkeys;
    $this->draw;
    return $this;
}

sub leave_curses() 
{
    my $this = shift;
    def_prog_mode(); 
    endwin();
}

sub reset_curses()
{
    my $this = shift;
    reset_prog_mode();
}

1;


=pod

=head1 NAME

Curses::UI - A curses based user user interface framework




=head1 SYNOPSIS

Here's the obligatory "Hello, world!" example.

    use Curses::UI;
    my $cui = new Curses::UI;
    $cui->dialog("Hello, world!");




=head1 DESCRIPTION

Curses::UI can be used for the development of curses
based user interfaces. Currently, it contains the 
following classes:

B<Base elements>

=over 4

=item * L<Curses::UI::Widget|Curses::UI::Widget>

=item * L<Curses::UI::Container|Curses::UI::Container>

=back

B<Widgets>

=over 4

=item * L<Curses::UI::Buttonbox|Curses::UI::Buttonbox>

=item * L<Curses::UI::Calendar|Curses::UI::Calendar>

=item * L<Curses::UI::Checkbox|Curses::UI::Checkbox>

=item * L<Curses::UI::Label|Curses::UI::Label>

=item * L<Curses::UI::Listbox|Curses::UI::Listbox>

=item * L<Curses::UI::Menubar|Curses::UI::Menubar>

=item * L<Curses::UI::MenuListbox|Curses::UI::MenuListbox> (used by Curses::UI::Menubar)

=item * L<Curses::UI::PasswordEntry|Curses::UI::PasswordEntry>

=item * L<Curses::UI::Popupmenu|Curses::UI::Popupmenu>

=item * L<Curses::UI::Progressbar|Curses::UI::Progressbar>

=item * L<Curses::UI::Radiobuttonbox|Curses::UI::Radiobuttonbox>

=item * L<Curses::UI::SearchEntry|Curses::UI::SearchEntry> (used by Curses::UI::Searchable)

=item * L<Curses::UI::TextEditor|Curses::UI::TextEditor>

=item * L<Curses::UI::TextEntry|Curses::UI::TextEntry>

=item * L<Curses::UI::TextViewer|Curses::UI::TextViewer>

=item * L<Curses::UI::Window|Curses::UI::Window>

=back

B<Dialogs>

=over 4

=item * L<Curses::UI::Dialog::Basic|Curses::UI::Dialog::Basic>

=item * L<Curses::UI::Dialog::Error|Curses::UI::Dialog::Error>

=item * L<Curses::UI::Dialog::Filebrowser|Curses::UI::Dialog::Filebrowser>

=item * L<Curses::UI::Dialog::Status|Curses::UI::Dialog::Status>

=back

B<Support classes>

=over 4

=item * L<Curses::UI::Common|Curses::UI::Common>

=item * L<Curses::UI::Searchable|Curses::UI::Searchable>

=back


=head1 OPTIONS

=over 4

=item B<-compat> < BOOLEAN >

If the B<-compat> option is set to a true value, the Curses::UI
program will run in compatibility mode. This means that only
very simple characters will be used for creating the widgets.
By default this option is set to false.

=item B<-clear_on_exit> < BOOLEAN >

If the B<-clear_on_exit> option is set to a true value,
a Curses::UI program will call the "clear" program on exit
(through the DESTROY method of Curses::UI). By default
this option is set to false.

=item B<-mouse_support> < BOOLEAN >

If the B<-mouse_support> option is set to a false value
mouse support will be disabled. This is used to override
the auto determined value and to disable mouse support.

=item * B<-userdata> < SCALAR >

This option specifies a user data that can be retrieved with
the B<userdata>() method.  It is usefull to store application's
internal data that otherwise would not be accessible in callbacks.

=back




=head1 METHODS

The UI is a descendant of Curses::UI::Container, so you can use the
Container methods. Here's an overview of the methods that are specific
for Curses::UI.

=over 4

=item B<new> ( OPTIONS )

Create a new Curses::UI instance. See the OPTIONS section above 
to find out what options can be used.

=item B<leave_curses> ( )

Temporarily leaves curses mode and recovers normal terminal
mode.

=item B<reset_curses> ( )

Return to curses mode after B<leave_curses()>.

=item B<add> ( ID, CLASS, OPTIONS )

The B<add> method of Curses::UI is almost the same as the B<add>
method of Curses::UI::Container. The difference is that Curses::UI
will only accept classes that are (descendants) of the
Curses::UI::Window class. For the rest of the information
see L<Curses::UI::Container|Curses::UI::Container>.

=item B<mainloop> ( )

Starts a Tk like main loop that will handle input and events.

=item B<MainLoop> ( )

Same as B<mainloop>, for Tk compatibility.

=item B<usemodule> ( CLASSNAME )

Loads the with CLASSNAME given module.

=item B<userdata> ( [ SCALAR ] )

This method will return the user internal data stored in the UI object.
If a SCALAR parameter is specified it will also set the current user
data to it.

=item B<layout> ( )

The layout method of Curses::UI will try to find out the size of the
screen. After that it will call the B<layout> routine of every 
contained object. So running B<layout> on a Curses::UI object will
effectively layout the complete application. Normally you will not 
have to call this method directly.

=item B<compat> ( [BOOLEAN] )

The B<-compat> option will be set to the BOOLEAN value, unless
BOOLEAN is omitted. The method returns the current value 
for B<-compat>.

=item B<clear_on_exit> ( [BOOLEAN] )

The B<-clear_on_exit> option will be set to the BOOLEAN value, unless
BOOLEAN is omitted. The method returns the current value 
for B<-clear_on_exit>.

=item B<dialog> ( MESSAGE or OPTIONS )

Use the B<dialog> method to show a dialog window. If you only
provide a single argument, this argument will be used as the 
message to show. Example:

    $cui->dialog("Hello, world!"); 

If you want to have some more control over the dialog window, you
will have to provide more arguments (for an explanation of the 
arguments that can be used, see 
L<Curses::UI::Dialog::Basic|Curses::UI::Dialog::Basic>. 
Example:

    my $yes = $cui->dialog(
        -message => "Hello, world?");
        -buttons => ['< Yes >','< No >']
        -values  => [1,0],
        -title   => 'Question',
    );

    if ($yes) {
        # whatever
    }
       

=item B<error> ( MESSAGE or OPTIONS )

The B<error> method will create an error dialog. This is 
basically a Curses::UI::Dialog::Basic, but it has an ASCII-art
exclamation sign drawn left to the message. For the rest 
it's just like B<dialog>. Example:

    $cui->error("It's the end of the\n"
               ."world as we know it!");

=item B<filebrowser> ( OPTIONS )

The B<filebrowser> method will create a file browser
dialog. For an explanation of the arguments that can be 
used, see L<Curses::UI::Dialog::Filebrowser|Curses::UI::Dialog::Filebrowser>.
Example:

    my $file = $cui->filebrowser(
        -path => "/tmp",
        -show_hidden => 1,
    );

    # Filebrowser will return undef
    # if no file was selected.
    if (defined $file) { 
        unless (open F, ">$file") {
            print F "Hello, world!\n";
            close F;
    } else {
            $cui->error("Error on writing to "
                       ."\"$file\":\n$!");
    }
    } 

=item B<loadfilebrowser>( OPTIONS )

=item B<savefilebrowser>( OPTIONS )

These two methods will create file browser dialogs as well.
The difference is that these will have the dialogs set up
correctly for loading and saving files. Moreover, the save
dialog will check if the selected file exists or not. If it
does exist, it will show an overwrite confirmation to check
if the user really wants to overwrite the selected file.

=item B<status> ( MESSAGE )

=item B<nostatus> ( )

Using these methods it's easy to provide status information for
the user of your program. The status dialog is a dialog with 
only a label on it. The status dialog doesn't really get the
focus. It's only used to display some information. If you need
more than one status, you can call B<status> subsequently.
Any existing status dialog will be cleaned up and a new one
will be created.

If you are finished, you can delete the status dialog by calling
the B<nostatus> method. Example:

    $cui->status("Saying hello to the world...");
    # code for saying "Hello, world!"

    $cui->status("Saying goodbye to the world...");
    # code for saying "Goodbye, world!"

    $cui->nostatus;

=item B<progress> ( OPTIONS )

=item B<setprogress> ( POSITION, MESSAGE )

=item B<noprogress> ( )

Using these methods it's easy to provide progress information
to the user. The progress dialog is a dialog with an optional
label on it and a progress bar. Similar to the status dialog,
this dialog does not get the focus. 

Using the B<progress> method, a new progress dialog can be 
created (see also 
L<Curses::IU::Dialog::Progress|Curses::UI::Dialog::Progress>). 
This method takes the same arguments as the Curses::IU::Dialog::Progress 
class.

After that the progress can be set using B<setprogress>. This 
method takes one or two arguments. The first argument is the current
position of the progressbar. The second argument is the message
to show in the label. If one of these arguments is undefined,
the current value will be kept. 

If you are finished, you can delete the progress dialog by calling
the B<noprogress> method. 

Example:

    $cui->progress(
        -max => 10,
    -message => "Counting 10 seconds...",
    );

    for my $second (0..10) {
    $cui->setprogress($second)
    sleep 1;
    }

    $cui->noprogress;

=back



=head1 SEE ALSO

L<Curses>
L<Curses::UI::Container|Curse::UI::Container>,




=head1 BASIC TUTORIAL

=head1 First requirements

Any perl program that uses Curses::UI needs to include
"use Curses::UI". A program should also use "use strict"
and the B<-w> switch to ensure the program is working
without common errors (but of course Curses::UI will work
without them). After that an instance of Curses::UI must
be created. From now on, this instance will be called
"the UI".

    #!/usr/bin/perl -w

    use strict;
    use Curses::UI;
    my $cui = new Curses::UI;

=head1 Create windows

After the initialization has been done, windows can be
added to the UI. You will always have to do this. It is not
possible to add widgets to the UI directly. Here is an
example that creates a window with a title and a border,
which has a padding of 2 (For the explanation of $cui->add, 
see the Curses::UI::Container manual page).

    my $win1 = $cui->add(
        'win1', 'Window',
        -border => 1,
        -title => 'My first Curses::UI window!',
        -pad => 2,
    );

Well... that's fun! Let's add another window! And let's
give it more padding, so that the window is smaller than
the previous one.
    
    my $win2 = $cui->add(
        'win2', 'Window',
        -border => 1,
        -title => 'My second Curses::UI window!',
        -pad => 6,
    );

=head1 Add some widgets

Now that we have a couple of windows, we can add widgets
to them. We'll add a popupmenu and some buttons to 
the first window.

    my $popup = $win1->add(
        'popup', 'Popupmenu',
        -x => 2,
        -y => 2,
        -sbborder => 1, 
        -values => [ 1, 2, 3, 4, 5 ],
        -labels => {
            1 => 'One', 
            2 => 'Two', 
            3 => 'Three', 
            4 => 'Four', 
            5 => 'Five', 
        },
    );

    my $but1 = $win1->add(
        'buttons', 'Buttonbox',
        -x => 2,
        -y => 4,
        -buttons => [
            { -label => '< goto window 2 >', -value => 'goto2' },
            { -label => '< Quit >', -value => 'quit' },
        ],
    ); 

We'll add a texteditor and some buttons to the second window. Look how
we can use padding to do some basic layouting. We do not specifiy the
with and height of the TextEditor widget, so the widget will stretch
out itself as far as possible. But because of the -padbottom option,
it will leave some space to put the buttons. By specifying a negative
-y offset for the buttons, we have a scalable application. Resize the
screen and the widgets will follow!
    
    my $editor = $win2->add(
        'editor', 'TextEditor',
        -border => 1,
        -vscrollbar => 1,
        -wrapping => 1,
        -x => 2,
        -y => 1,
        -padright => 2,
        -padbottom => 3,
    );

    my $but2 = $win2->add(
        'buttons', 'Buttonbox',
        -x => 2,
        -y => -2,
        -buttons => [
            { -label => '< goto window 1 >', -value => 'goto1' },
            { -label => '< Quit >', -value => 'quit' },
        ],
    );

=head1 Specify when the windows will loose their focus

We have a couple of buttons on each window. As soon as a 
button is pressed, it will have the window loose its
focus (buttons will have any kind of Container object
loose its focus). You will only have to do something
if this is not the desired behaviour. 

If you want the buttons themselves to loose focus if 
pressed, then change its routine for the "return" 
binding from "LEAVE_CONTAINER" to "LOOSE_FOCUS". Example:

    $but1->set_routine('loose-focus', 'LOOSE_FOCUS');

To make things a bit more snappy, we want to add some
shortcut keys to the appliction:

    CTRL+Q : Quit the application
    CTRL+N : Go to the next window

This can be done by assigning "returnkeys" to a window.
Each widget in the window will get extra keybindings to
have the window loose its focus if one of the returnkeys
is pressed. For our application we can set the desired
shortcut keys like this:

    $win1->returnkeys("\cN", "\cQ");
    $win2->returnkeys("\cN", "\cQ");

From now on both windows will loose focus if either CTRL+Q
or CTRL+N is pressed. Important: make sure that returnkeys 
are assigned to a window _after_ all windgets have been 
added. 

=head1 The main loop

The main loop is called by

    $cui->MainLoop;

=head1 Add a good-bye dialog

Curses::UI has a couple of methods that are easy for showing dialogs 
(see the METHODS section below). We'll use a dialogbox to say goodbye
to the user of our program. After the mainloop we add:

    $cui->dialog("Bye bye!");

=head1 You're done!

We have built a genuine Curses::UI application! Not that it is a
very useful one, but who cares? Now try out if it works like you 
think it should. The complete source code of this application can 
be found in the examples directory of the distribution 
(examples/demo-Curses::UI).




=head1 AUTHOR

Copyright (c) 2001-2002 Maurice Makaay. All rights reserved.

Maintained by Marcus Thiesen (marcus@cpan.thiesenweb.de)

This package is free software and is provided "as is" without express
or implied warranty. It may be used, redistributed and/or modified
under the same terms as perl itself.

