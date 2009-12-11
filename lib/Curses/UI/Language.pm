# ----------------------------------------------------------------------
# Curses::UI::Language
#
# (c) 2001-2002 by Maurice Makaay. All rights reserved.
# This file is part of Curses::UI. Curses::UI is free software.
# You can redistribute it and/or modify it under the same terms
# as perl itself.
#
# Currently maintained by Marcus Thiesen
# e-mail: marcus@cpan.thiesenweb.de
# ----------------------------------------------------------------------

package Curses::UI::Language;

my $default_lang = 'English';

my %lang_alias = (
    'en'        => 'english',
    'uk'        => 'english',

    'du'        => 'dutch',
    'nl'        => 'dutch',
);

sub new()
{
    my $class = shift;
    my $lang  = shift; 

    my $this = {
	-tags => {},
	-lang => undef,
    };
    bless $this, $class;

    # Load english tags so these can be used
    # as a fallback for other languages.
    $this->loadlanguage('english');

    # Load the wanted language.
    $this->loadlanguage($lang);

    return $this;
}

sub loadlanguage($;)
{
    my $this = shift;
    my $lang = shift;

    # Construct the language module to use.
    $lang = $default_lang unless defined $lang;
    $lang =~ s/[^\w\_]//g;
    $lang = lc $lang;
    $lang = $lang_alias{$lang} if defined $lang_alias{$lang};

    # Loading the same language twice is not very useful.
    return $this if defined $this->{-lang} and 
                    $lang eq $this->{-lang};

    # Determine classname and filename for the language package.
    my $l_class = "Curses::UI::Language::${lang}";
    my $l_file  = "Curses/UI/Language/${lang}.pm";

    # Load the language package.
    require $l_file;

    # Save the name of the currently loaded language.
    $this->{-lang} = $lang;

    # Create a filehandle to the __DATA__ section 
    # of the language package.
    local *LANG_DATA = $l_class . '::DATA';
    
    # Save __DATA__ filehandle position.
    my $data_start = tell(LANG_DATA);

    # Read and store tags/blocks.
    my $tag   = undef;
    my $block = '';
    LINE: while (<LANG_DATA>) {
	if (m/^#/) {
	    next LINE;
	}
	elsif (m/^\s*\[\s*(.*)\s*\]\s*(.*)$/) {
	    my $oldtag = $tag;
	    $tag = $1;
	    $this->store($oldtag, $block);
	    $block = $2; 
	    $block = '' unless defined $block;
	}
	elsif (defined $tag) {
	    $block .= "$_";
	}
	elsif (!m/^\s*$/) {
	    warn "$l_file, line $.: found data outside tag block\n";
	}
    }
    $this->store($tag, $block);

    # Reset __DATA__ filehandle.
    seek(LANG_DATA, $data_start, 0);

}

sub store($$;)
{
    my $this  = shift;
    my $tag   = shift;
    my $block = shift;

    return $this unless defined $tag;

    # Remove empty start- and endlines.
    my @block = split /\n/, $block;
    while (@block and $block[0]  =~ /^\s*$/) { shift @block }
    while (@block and $block[-1] =~ /^\s*$/) { pop @block   }

    $this->{-tags}->{lc $tag} = join "\n", @block;

    return $this;
}


sub get($;)
{
    my $this  = shift;
    my $tag   = shift;

    my $block = $this->{-tags}->{$tag};
    unless (defined $block) {
        warn "get(): no language block for tag '$tag'";
	$block = '';
    }

    return $block;
}

sub getarray($;)
{
    my $this = shift;
    my $tag  = shift;

    my $block = $this->get($tag); 
    return () unless defined $block;

    $block =~ s/\n/ /g;
    return split " ", $block;
}


1;
