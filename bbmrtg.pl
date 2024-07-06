#!/usr/bin/perl
#
# bbmrtg.pl: Check the status of MRTG targets and report status to Big Brother
#
# "perldoc bbmrtg.pl" for more instructions on installation, configuration and use
# of this script. 
#
# Version:  1.8
#
# Maintainers:
#
#         1.0  Sam Denton, denton@wantec.com
#         1.1  Craig Cook
#         1.3  Robert-Andre Croteau
#         1.5  Craig Cook
#         1.6+ Al Payne
#

use strict;

##################################
# CONFIGURATION SECTION
##################################
# Run 'perldoc bbmrtg.pl' for detailed information about
# each of the following configuration options.

# Define the full path to the MRTG_lib module.
#use lib '/usr/local/lib/perl5/site_perl/5.8.8/';  # aka '~mrtg/lib/mrtg2'
use lib '/usr/share/perl5/';

# Define the full path to the MRTG .cfg file.
# UNIX
my $MRTGCFG = '/var/www/html/mrtg/mrtg.cfg';  # aka '~mrtg/mtrg.cfg'

# WIN NT/W2K
#my $MRTGCFG = 'c:/mrtg/mrtg-2.9.25/bin/mrtg.cfg';  # aka '~mrtg/mtrg.cfg'

# Define the base URL of your bb server if necessary.
#my $MRTGBASEURL = 'http://192.168.1.1';  
my $MRTGBASEURL = 'http://192.168.9.12/mrtg';

# Define the path to the MRTG HTML files are.
my $HTMLDIR = 'mrtg';           

# Define the path to the MRTG graph images.
my $IMGDIR = 'mrtg/images';  

# Define the path to the Big Brother GIF files.
my $GIFSDIR = '/hobbit/gifs'; 

# Define the image type (gif/png).
my $IMGTYPE = 'png';

# Define the status level at which to show details for interfaces.
my $SHOWDETAIL = 'always';

# Define the status level at which to show the MRTG graph.
#my $SHOWGRAPH = 'red';
my $SHOWGRAPH = 'red';

# Define the status level at which to display rules in the status logs.
#my $SHOWRULES = 'yellow';
my $SHOWRULES = 'never';

# Define the status level at which a graph should be moved to the page top.
my $SHOWTOP = 'yellow';

# Define if BB should generate a purple status if MRTG stops reporting.
my $PURPLECHECK = 1;

# Define how old (in minutes) an MRTG .log file can be before it's stale.
my $MRTGSTALE = 86400;

# Define code for < and > (&lt; and &gt; don't work in default BB config)
my $LTSYMBOL = "&lt;";
my $GTSYMBOL = "&gt;";

# Define the BACKEND MRTG is using using (RRDtool or just MRTG).
my $BACKEND = 'RRD';  # RRD or MRTG

# --- Start of RRDtool BACKEND settings (only used if $BACKEND = 'RRD')

    # Define your RRD cgi script: mrtg-rrd.cgi or 14all.cgi or routers2.cgi
    my $MRTGCGI='14all.cgi';

    # Define your web server CGI directory
    my $CGIDIR = "";

    # Define the period of time for the graph to show in BB
    my $GRAPHPERIOD = "daily";

    # Define the path to your RRDs module, if perl can't find it by default.
    use lib '/usr/local/lib/perl5/site_perl/5.8.8/mach/';
# --- End of RRDtool BACKEND settings

# --- Start of Windows specific settings

    # Define location for saved logs.
    my $SAVEDLOGDIR = 
            'c:/Program Files/Quest Software/Big Brother/BBNT/logs';

    # Define how long to sleep before writing next log 
    # ( >"logs timer" in bbntcfg.exe )
    my $BBNTSLEEP = 2; # How long to sleep before writing next log

# --- End of Windows specific settings

##################################
# Start of script
##################################

$ENV{BBPROG} = 'bbmrtg';

use MRTG_lib;

if ($BACKEND eq 'RRD') {
    use RRDs;
    $HTMLDIR = $IMGDIR = "$CGIDIR/$MRTGCGI";
}

sub percent
{
    return sprintf("%.1f%%", 100*$_[0]/$_[1]);
}

my %priority = (
    'never'  => 6,
    'red'    => 5,
    'purple' => 4,
    'yellow' => 3,
    'green'  => 2,
    'clear'  => 1,
    'always' => 0,
    );

# my $BBMRTGID = $$;
my $tron = $ENV{TRON};

my $mrtgStaleSecs = 60 * $MRTGSTALE;
my $imageDim = 'HEIGHT=16 WIDTH=16 BORDER=0';

my (@targets, %globalcfg, %targetcfg);
readcfg($MRTGCFG, \@targets, \%globalcfg, \%targetcfg);

my %status;     # per-system status
my %info;       # detailed status
my %index;      # fallback html link
my %hostname;   # BB hostname
my %svcs;       # Service name associated with host


foreach my $target (@targets) {
    warn "processing target: $target...\n" if $tron;
    warn "processing targetcfg: $targetcfg{'bb*host'}{$target}...\n" if $tron;
    my $host = $targetcfg{'bb*host'}{$target};
    warn "host: $host...\n" if $tron;
    unless ($host) {
        warn "Missing bb*host[$target] in $MRTGCFG\n" if $tron;
        next;
    }
    if ($host =~ /[<>]/) {
        warn "Host name seems to contain HTML.  See the perldoc.";
        next;
    }

    my $title     = $targetcfg{'title'}{$target}     || $target;
    my $maxbytes  = $targetcfg{'maxbytes'}{$target}  || 64000;
    my $maxbytesi = $targetcfg{'maxbytes1'}{$target} || $maxbytes;
    my $maxbyteso = $targetcfg{'maxbytes2'}{$target} || $maxbytes;
    my $directory = $targetcfg{'directory'}{$target};
    my $svc       = $targetcfg{'bb*svc'}{$target}    || 'mrtg';
    my $althost   = $targetcfg{'bb*althost'}{$target};          # host to link interface to
    my $altsvc    = $targetcfg{'bb*altsvc'}{$target} || 'mrtg'; # column name for host link above
    my $yellow    = $targetcfg{'bb*yellow'}{$target} ||
            (($title =~ /ethernet/i) ? '40%' : '70%');
    my $red       = $targetcfg{'bb*red'}{$target}    ||
            (($title =~ /ethernet/i) ? '60%' : '85%');
    my $unit      = $targetcfg{'bb*unit'}{$target}   ||
                    $targetcfg{'shortlegend'}{$target} || 'bits/sec';
    my $in        = $targetcfg{'bb*in'}{$target}     ||
                    $targetcfg{'legendi'}{$target}   || 'In';
    my $out       = $targetcfg{'bb*out'}{$target}    ||
                    $targetcfg{'legendo'}{$target}   || 'Out';
    my $colors    = $targetcfg{'colours'}{$target}   || 'GREEN#00eb0c,BLUE#1000ff';
    my $factor    = $targetcfg{'factor'}{$target}    || 1;   

    # Load MRTG parameters from "options" config line
    my $noo = 
        (defined($targetcfg{'legendo'}{$target}) && ($targetcfg{'legendo'}{$target} eq '')) || 
        $targetcfg{'options'}{$target} =~ /noo/;
    my $noi = 
        (defined($targetcfg{'legendi'}{$target}) && ($targetcfg{'legendi'}{$target} eq '')) ||
        $targetcfg{'options'}{$target} =~ /noi/;
    my $nopercent = ($targetcfg{'options'}{$target} =~ /nopercent/);

    warn <<__VARS__ if $tron;
\$title     = '$title'
\$maxbytesi = '$maxbytesi'
\$maxbyteso = '$maxbyteso'
\$directory = '$directory'
\$svc       = '$svc'
\$althost   = '$althost'
\$altsvc    = '$altsvc'
\$yellow    = '$yellow'
\$red       = '$red'
\$unit      = '$unit'
\$in        = '$in'
\$out       = '$out'
\$colours   = '$colors'
\$factor    = '$factor'
\$noo       = '$noo'
\$noi       = '$noi'
\$nopercent = '$nopercent'

__VARS__

    my $routers2_target = $target; 
    $target = "$directory/$target" if $directory;

    my ($htmlUrl, $imgUrl, $targetLog);
    if ($BACKEND eq 'MRTG') {
        $htmlUrl = "$MRTGBASEURL/$HTMLDIR/$target.html";
        $imgUrl = "$MRTGBASEURL/$IMGDIR/$target-day.$IMGTYPE";
        $targetLog = "$globalcfg{workdir}/$target.log";
    } elsif ($BACKEND eq 'RRD') {
        if ($MRTGCGI eq '14all.cgi') {
            $imgUrl = "$MRTGBASEURL/$directory/$HTMLDIR?log=$routers2_target\&png=daily";
            $htmlUrl = "$MRTGBASEURL/$directory/$HTMLDIR?log=$routers2_target";
        } elsif ($MRTGCGI eq 'mrtg-rrd.cgi') {
            $imgUrl = "$MRTGBASEURL/$IMGDIR/$target-$GRAPHPERIOD.$IMGTYPE";
            $htmlUrl = "$MRTGBASEURL/$HTMLDIR/$target.html";
        } elsif ($MRTGCGI eq 'routers2.cgi') {
	            $imgUrl = "$MRTGBASEURL/$HTMLDIR?rtr=master.cfg&if=$routers2_target&xgtype=d&page=image";
	            $htmlUrl = "$MRTGBASEURL/$HTMLDIR?" .
                           "rtr=master.cfg&bars=Cami&page=graph&xgtype=dwmy&xgstyle=l2&if" .
                           "=$routers2_target&xmtype=options";
        } else {
            die "MRTG CGI program '$MRTGCGI' not supported\n";
        }
        if (defined($globalcfg{logdir})) {
            $targetLog = "$globalcfg{logdir}/$target.rrd";
        } else {
            $targetLog = "$globalcfg{workdir}/$target.rrd";
        }
    } else {
        die "BACKEND '$BACKEND' not supported (must be RRD or MRTG)\n";
    }

    warn "... targetlog $targetLog\n" if $tron;
    unless (-s "$targetLog") {
        warn "bbmrtg.pl: MRTG file -> <$targetLog> is invalid\n";
        next;
    }


    my $bbfile = $host;
    if ($bbfile =~ /<TABLE>/) {
        warn "Host name is invalid.  Do not put bb*host[]: on the line after\n
              PageTop in your mrtg.cfg file.  Put it directly after\n
              the Target[]: line\n";
        next;
    }
         
    if ( $^O ne "MSWin32" ) {
        $bbfile =~ s/\..*// unless $ENV{FQDN} eq 'TRUE';
    }
    $bbfile =~ s/\./,/g;
    $bbfile .= ".$svc";
    warn "... bbfile $bbfile\n" if $tron;

    $hostname{$bbfile} = $host;
    $svcs{$bbfile} = $svc;

    $index{$bbfile} ||= "$MRTGBASEURL/$HTMLDIR/$directory/index.html"
        if $directory;

    # alternate host
    my $bbaltfile = $althost;
    if ($bbaltfile) {
        if ($^O ne "MSWin32") {
            $bbaltfile =~ s/\..*// unless $ENV{FQDN} eq 'TRUE';
        }
        $bbaltfile =~ s/\./,/g;
        $bbaltfile .= ".$altsvc";
        $hostname{$bbaltfile} = $althost;
        $svcs{$bbaltfile} = $altsvc;
        warn "... bbaltfile $bbaltfile\n" if $tron;
    }

    my ($yi_min, $yo_min, $yi_max, $yo_max);
    my @F = split(/:/, $yellow);
    if (scalar @F == 1) {
        $yi_min = $yo_min = 0;
        $yi_max = $yo_max = $F[0];
    } elsif (scalar @F == 2) {
        $yi_min = $yo_min = $F[0];
        $yi_max = $yo_max = $F[1];
    } elsif (scalar @F == 4) {
        $yi_min = $F[0];
        $yi_max = $F[1];
        $yo_min = $F[2];
        $yo_max = $F[3];
    } else {
        warn "bbmrtg.pl: invalid bb*yellow parameter for $host $svc, skipping\n";
        next;
    }

    my ($ri_min, $ro_min, $ri_max, $ro_max);
    @F = split(/:/, $red);
    if (scalar @F == 1) {
        $ri_min = $ro_min = 0;
        $ri_max = $ro_max = $F[0];
    } elsif (scalar @F == 2) {
        $ri_min = $ro_min = $F[0];
        $ri_max = $ro_max = $F[1];
    } elsif (scalar @F == 4) {
        $ri_min = $F[0];
        $ri_max = $F[1];
        $ro_min = $F[2];
        $ro_max = $F[3];
    } else {
        warn "bbmrtg.pl: invalid bb*red parameter for $host $svc, skipping\n";
        next;
    }

    foreach (($yi_min, $yi_max, $ri_min, $ri_max, $yo_min, $yo_max, $ro_min, $ro_max)) {
        $_ *= $maxbytesi / 100 if /%/;
        $_ += 0;
    }

    my ($last, $i_now, $o_now);
        if ($BACKEND eq 'MRTG') {
        warn "open(MRTG, '$targetLog')\n" if $tron;
        open(MRTG, $targetLog) or next;
        <MRTG>;
        ($last, $i_now, $o_now) = split(/\s+/, <MRTG>);
        warn "... \$i_now=$i_now, \$_=$_\n" if $tron;
        close MRTG;
    } elsif ($BACKEND eq 'RRD') {
        $last = RRDs::last($targetLog);
	my $newlast = $last - 300;
        my ($start, $step, $names, $data)
            = RRDs::fetch "-s $newlast","-e $newlast", $targetLog, 'AVERAGE';
        foreach my $dat (@$data) {
            if (defined($$dat[0])) {
               $i_now=($factor * $$dat[0]);
            }
            if (defined($$dat[1])) {
                $o_now=($factor * $$dat[1]);
            }
        }

        warn "last: $last, i_now: $i_now, o_now: $o_now\n" if $tron;
    } else {
        die "BACKEND '$BACKEND' not supported\n";
    }

    my $current_time = $^T;
    my $timediff = $current_time - $last;
    my $color = 'clear';
    warn "... timediff $timediff, last $last, stale $mrtgStaleSecs\n" if $tron;

    if ($timediff >= 0) {
        # If we want to provoke a purple status for stale MRTG logs, don't update.
        next if $PURPLECHECK && $timediff > $mrtgStaleSecs;

        if ($noo) {
            $color =
                $i_now > $ri_max || $i_now < $ri_min 
                    ? 'red' :
                $i_now > $yi_max || $i_now < $yi_min 
                    ? 'yellow' : 'green';
            warn <<__COLOR__ if $tron;
            $color =
                $i_now > $ri_max || $i_now < $ri_min 
                    ? 'red' :
                $i_now > $yi_max || $i_now < $yi_min 
                    ? 'yellow' : 'green';
__COLOR__
        } elsif ($noi) {
            $color =
                $o_now > $ro_max || $o_now < $ro_min 
                    ? 'red' :
                $o_now > $yo_max || $o_now < $yo_min 
                    ? 'yellow' : 'green';
            warn <<__COLOR__ if $tron;
            $color =
                $o_now > $ro_max || $o_now < $ro_min 
                    ? 'red' :
                $o_now > $yo_max || $o_now < $yo_min 
                    ? 'yellow' : 'green';
__COLOR__
        } else {
            $color =
                $i_now > $ri_max || $o_now > $ro_max ||
                $i_now < $ri_min || $o_now < $ro_min
                    ? 'red' :
                $i_now > $yi_max || $o_now > $yo_max ||
                $i_now < $yi_min || $o_now < $yo_min
                    ? 'yellow' : 'green';
            warn <<__COLOR__ if $tron;
            $color =
                $i_now > $ri_max || $o_now > $ro_max ||
                $i_now < $ri_min || $o_now < $ro_min
                    ? 'red' :
                $i_now > $yi_max || $o_now > $yo_max ||
                $i_now < $yi_min || $o_now < $yo_min
                    ? 'yellow' : 'green';
__COLOR__
        }
    } else {
        warn "Time stamp in log is in the future by $timediff secs!\n";
        warn "Target: $target, bbfile: $bbfile\n";
        warn "current time: $current_time, last $last, stale $mrtgStaleSecs\n";
        warn "purplecheck: $PURPLECHECK\n" ;
    }

    if ($priority{$color} > $priority{$status{$bbfile}}) {
        $status{$bbfile} = $color;
    }
    if ($bbaltfile && ($priority{$color} > $priority{$status{$bbaltfile}})) {
        $status{$bbaltfile} = $color;
    }
    warn "... status $color\n" if $tron;
    next if ($priority{$color} < $priority{$SHOWDETAIL});

    # Adjust the precision
    my ($precFactor, $precision);
    if ($unit =~ /^kb/i) {
        $precFactor = 1024;
        $precision = 2;
    } elsif ($unit =~ /^mb/i) {
        $precFactor = 1024*1024;
        $precision = 3;
    } elsif ($unit =~ /^gb/i) {
        $precFactor = 1024*1024*1024;
        $precision = 3;
    } elsif ($unit =~ /^tb/i) {
        $precFactor = 1024*1024*1024*1024;
        $precision = 3;
    } else {
        $precFactor = 1;
        $precision = 0;
    }

    my $pi_now = percent($i_now, $maxbytesi);
    my $po_now = percent($o_now, $maxbyteso);

    $i_now = sprintf("%0.${precision}d", $i_now / $precFactor * 8);
    $o_now = sprintf("%0.${precision}d", $o_now / $precFactor * 8);

    my $statusline;

    $statusline = "&$color<A HREF=\"$htmlUrl\">$title:</A> ";
    if (!$noi) {
        $statusline .= "$in: $i_now $unit ";
        if (!$nopercent) {
            $statusline .= "($pi_now) ";
        }
    }
    if (!$noo) {
        $statusline .= "$out: $o_now $unit ";
        if (!$nopercent) {
            $statusline .= "($po_now) ";
        }
    }

    unless ($priority{$color} < $priority{$SHOWGRAPH}) {
        $statusline .= <<__GRAPH__;
<CENTER><BR><A HREF="$htmlUrl"><IMG SRC="$imgUrl" ALT="Last 24 Hours" BORDER=0></A><BR></CENTER>
__GRAPH__
    }
    $statusline .= "\n";

    unless ($priority{$color} < $priority{$SHOWRULES}) {
        # Rules table variables (y=yellow, r=red, i=in, o=out)
        my ($disp_yi_min, $disp_yo_min, $disp_yi_max, $disp_yo_max, $disp_ri_min, $disp_ro_min, $disp_ri_max, $disp_ro_max);
        if ($nopercent) {
            $disp_yi_min = $yi_min . " " . $unit;
            $disp_yo_min = $yo_min . " " . $unit;
            $disp_yi_max = $yi_max . " " . $unit;
            $disp_yo_max = $yo_max . " " . $unit;
            $disp_ri_min = $ri_min . " " . $unit;
            $disp_ro_min = $ro_min . " " . $unit;
            $disp_ri_max = $ri_max . " " . $unit;
            $disp_ro_max = $ro_max . " " . $unit;
        } else {
            $disp_yi_min = percent($yi_min, $maxbytesi);
            $disp_yo_min = percent($yo_min, $maxbyteso);
            $disp_yi_max = percent($yi_max, $maxbytesi);
            $disp_yo_max = percent($yo_max, $maxbyteso);
            $disp_ri_min = percent($ri_min, $maxbytesi);
            $disp_ro_min = percent($ro_min, $maxbyteso);
            $disp_ri_max = percent($ri_max, $maxbytesi);
            $disp_ro_max = percent($ro_max, $maxbyteso);
        }
        my @col = split(/\,/,$colors,2);
        my $col_in  = $col[0];
        my $col_out = $col[1];
        $col_in =~ s/^.*#/#/g;
        $col_out =~ s/^.*#/#/g;
        $statusline .= <<"__START__";
<TABLE BORDER=1 ALIGN=CENTER> 
 <TR>
  <TH COLSPAN=6><B>Rules</B></TH>
 </TR>
__START__
        $statusline .= <<"__INCOMING__" unless $noi;
 <TR>
  <TD><FONT COLOR=$col_in><B>$in</B></FONT></TD>
  <TD BGCOLOR=red><FONT COLOR=black><B>$LTSYMBOL ${disp_ri_min}</B></FONT></TD>
  <TD BGCOLOR=yellow><FONT COLOR=black><B>$LTSYMBOL ${disp_yi_min}</B></FONT></TD>
  <TD BGCOLOR=green><FONT COLOR=black><B>${disp_yi_min} - ${disp_yi_max}</B></FONT></TD>
  <TD BGCOLOR=yellow><FONT COLOR=black><B>$GTSYMBOL ${disp_yi_max}</B></FONT></TD>
  <TD BGCOLOR=red><FONT COLOR=black><B>$GTSYMBOL ${disp_ri_max}</B></FONT></TD>
 </TR>
__INCOMING__
        $statusline .= <<"__OUTGOING__" unless $noo;
 <TR>
  <TD><FONT COLOR=$col_out><B>$out</B></FONT></TD>
  <TD BGCOLOR=red><FONT COLOR=black><B>$LTSYMBOL ${disp_ro_min}</B></FONT></TD>
  <TD BGCOLOR=yellow><FONT COLOR=black><B>$LTSYMBOL ${disp_yo_min}</B></FONT></TD>
  <TD BGCOLOR=green><FONT COLOR=black><B>${disp_yo_min} - ${disp_yo_max}</B></FONT></TD>
  <TD BGCOLOR=yellow><FONT COLOR=black><B>$GTSYMBOL ${disp_yo_max}</B></FONT></TD>
  <TD BGCOLOR=red><FONT COLOR=black><B>$GTSYMBOL ${disp_ro_max}</B></FONT></TD>
 </TR>
__OUTGOING__
        $statusline .= <<"__END__";
</TABLE>
<BR>
__END__
    }
    if ($priority{$color} >= $priority{$SHOWTOP}) {
        $info{$bbfile}{top} .= $statusline;
    } else {
        $info{$bbfile}{button} .= $statusline;
    }
    $info{$bbaltfile}{button} .= $statusline if $bbaltfile;
}

# Send status to the display server
my $now = localtime($^T) . "\n";
foreach (keys %status) {
    warn "processing $_...\n" if $tron;
    my $statusout = $now . $info{$_}{top} . $info{$_}{button};
    $statusout ||= <<__INDEX__ if $index{$_};
<IMG SRC="$GIFSDIR/$status{$_}.gif" ALT="$status{$_}" $imageDim>
<A HREF="$index{$_}">View graphs...</A>
__INDEX__
#    $statusout =~ s/>\s+</></g;
#    $statusout =~ s/>\n/>/g;
    if ( $^O ne "MSWin32" ) {
        system(
#               $ENV{BB} || '/bin/echo',
               $ENV{BB} || '/usr/lib/xymon/client/bin/xymon',
               $ENV{BBDISP} || 'localhost',
#               $ENV{BBDISP} || 'hxymon01',
               "status $_ $status{$_} $statusout",
              );
    } else {
        unlink "${SAVEDLOGDIR}/$svcs{$_}.tmp";
        open STAT , ">>${SAVEDLOGDIR}/$svcs{$_}.tmp";
        print STAT "$hostname{$_}:$status{$_} ";
        print STAT "$statusout\r\n";
        close STAT;
        my $from = "${SAVEDLOGDIR}/$svcs{$_}.tmp" ;
        my $to = "${SAVEDLOGDIR}/$svcs{$_}";
        rename $from , $to;
        sleep $BBNTSLEEP;
    }
}




=head1 NAME

bbmrtg.pl: Checks the status of MRTG targets and reports to Hobbit / Big Brother.

=head1 SYNOPSIS

This script merges MRTG gathered information into Hobbit / Big Brother (or
compatible systems).  It is intended that this be run as an external
script by Hobbit / Big Brother.

The script does not need to run on the display server, but must run on a host that 
has access to the MRTG data files.  If you are running this script on a host other 
than the display server, the appropriate Hobbit or Big Brother client
needs to run on this host so that the reports can be forwarded to the display server.

=head1 DESCRIPTION

=head2 Installation

=over 3

=over 3

NOTE: $BBHOME should be replaced with $HOBBITHOME on Hobbit installs.

=back

=item 1. 

Copy bbmrtg.pl to the $BBHOME/ext directory on the host reading the MRTG data.

=item 2. 

Customize the script as described in the next section.  Several variables will 
need to be defined in order for the script to work at all.

=item 3. 

Make sure execute permissions are set on it (chmod 500 bbmrtg.pl).

=item 4.

Tell the client to run the script:

B<Big Brother>

On *NIX installations, add bbmrtg.pl to $BBHOME/etc/bb-bbexttab.

On Windows installations, add bbmrtg.pl script to the "Externals list" in 
bbntcfg.exe.

B<Hobbit>

On Hobbit installs, bbmrtg needs to be added to $HOBBITHOME/etc/hobbitlaunch.cfg
as follows:

 [bbmrtg]
     ENVFILE $HOBBITHOME/etc/hobbitserver.cfg
     CMD $HOBBITHOME/ext/bbmrtg.pl
     LOGFILE $BBSERVERLOGS/bbmrtg.log
     INTERVAL 5m

=back 

=head2 Customization of bbmrtg.pl

There are several variables at the top of the bbmrtg.pl script that should 
be configured for your environment.

=head3 MRTG_lib module

=over 3

=item B<use lib> <MRTG_lib module path>

This script uses the MRTG_lib module to read MRTG config file.
Modify the 'use lib' statement to point to the directory where the
module is located.

=item B<$MRTGFG>

The MRTG-lib module needs to be told where the MRTG config file is.
Set B<$MRTGCFG> the full path name of the config file.

=back 

=head3 MRTG web server

This script builds MRTG related URLs using B<$MRTGBASEURL>, B<$HTMLDIR>, and 
B<$IMGDIR>.  The image type being generated by MRTG also needs to be defined.

=over 3

=item B<$MRTGBASEURL>

If your environment requires you to define the URL for your MRTG server, set
B<$MRTGBASEURL> to the appropriate URL.  This is required if your MRTG server 
was not running on the display server.

=item B<$HTMLDIR>

This variable defines the URL path to the MTRG HTML files.  The path defined in 
B<$HTMLDIR> is the relative path under the base URL, and will be used to create
URLS to the MRTG HTML files:

=over 3

MRTG HTML file URL = C<B<$MRTGBASEURL>/B<$HTMLDIR>>

=back

=item B<$IMGDIR>

This variable defines the URL path to the MRTG image files.  Similar to the 
above, the path defined in B<$IMGDIR> is the relative path under the base URL.

=over 3

MRTG image file URL =  C<B<$MRTGBASEURL>/B<$IMGDIR>>

=back

=item B<$IMGTYPE>

The B<$IMGTYPE> variable defines the image type your MRTG installation is 
generating.  Currently supported values are C<GIF> and C<PNG>.

=back

=head3 Display server settings

The path to Hobbit / Big Brother status gifs can be configured if you're using themes 
that sit in custom paths.

=over 3

=item B<$GIFSDIR>

Define the relative URL path to your theme gifs on your Hobbit / Big Brother display 
server.

=back

=head3 Status definitions

Serveral status levels can be customized to define when information and graphs 
will be displayed within the Hobbit / Big Brother detail pages.  The valid status levels 
are ranked in the following order:

    never  => 6
    red    => 5
    purple => 4
    yellow => 3
    green  => 2
    clear  => 1
    always => 0

Status settings define the minimum level at which a the script will display the 
associated information at.  Defining an action to take place at a status level
of C<yellow> will result in the action occuring for all yellow, purple, and red 
status messages.

=over 3

=item B<$SHOWDETAIL>

This defines the status level for showing the text information details of the 
MRTG results for a target.

=item B<$SHOWGRAPH>

This defines the status level for displaying the associated MRTG graph of the 
results for a target.

=item B<$SHOWRULES>

This defines the status level for displaying the rules BBMRTG used to determine
the status level.  The rules are displayed as an HTML table below the graph.  
If you expect to more than three interfaces with the same status, this should
be defined to C<yellow> or higher to prevent the status log from being truncated.

=item B<$SHOWTOP>

This defines the status level at which the specific MRTG results will be moved
to the top of the details page for the host.  Use this variable to move high
priority events to the top of the page if you wish to ensure they are seen 
first.

=item B<$PURPLECHECK>

This variable tells BBMRTG whether or not to consider MRTG files stale after a
period of time and no longer report on that target.  This results in Big 
Brother generating a purple status for that target if MRTG stops reporting.
This is usually on (C<1>).

=item B<$MRTGSTALE>

The script will consider an MRTG file stale after a file is more than 
B<$MRTGSTALE> minutes old.  If B<$PURPLECHECK> is on, then files Hobbit / Big Brother
will show a purple status after B<$MRTGSTALE> + B<$ENV{PURPLEDELAY}> minutes.
B<$ENV{PURPLEDELAY}> is defined in bbdef-server.sh, and is usually 30 minutes.

=back

=head3 General Hobbit / Big Brother settings

By default, Hobbit / Big Brother will filter the C<&> and C<;> symbols on an incoming 
message to the BB server.  The B<CLEANCHARS> string in bbdef-server.sh needs
to have these two strings removed in order to display those symbols.

=over 3

=item B<$LTSYMBOL>

=item B<$GTSYMBOL>

These two values define the character(s) to use when displaying rules to show 
less than and greater than rules.  If B<CLEANCHARS> has been changed, then
C<&lt;> and C<&gt;> will work, otherwise other strings need to be used (e.g.,
C<LT> and C<GT>).  

Alternatively bbd.c can be patched to support an additional run option of 
C<LTGTALLOWED> which adds support for just those two strings without exposing 
the server to any additional risks associated with allowing those characters. A
patch for bbd.c is available from 
L<http://www.pleiades.com/patches/mrtgbb.html>.


=back

=head3 Backend configuration

BBMRTG currently supports both RRDtool and MRTG type data files for retrieving
MRTG results.  If you are using RRDtool with MRTG there are several additional
configuration options avaialble.

=over 3

=item B<$BACKEND>

Set to C<RRD> if you use RRDtool with MRTG, or C<MRTG> if not.

=back

=head4 RRDtool configuration options

If you use RRDtool, you will need to define the CGI script you are using and
where it resides on the server.  You can also optionally define the graph to 
display.

=over 3

=item B<$MRTGCGI>

This variable holds the name of the RRD cgi script you are using. Valid values
are C<mrtg-rrd.cgi>, C<14all.cgi>, and C<routers2.cgi>.

=item B<$CGIDIR>

This defines the location the B<$MRTGCGI> script above.  The location is the 
relative URL path to your CGI script.  This value is used to adjust the 
B<$HTMLDIR> value if a CGI script is being used to dynamically generate your
MRTG graphs.

=item B<$GRAPHPERIOD>

This variable defines the time period of the graph to display.
Valid values are:

    fourhour *
    day
    week
    month
    year

B<NOTE:> C<fourhour> is only a valid option if using a version of mrtg-rrd.cgi 
that supports the creation of four hour graphs.  To my knowledge neither 
C<14all.cgi> or C<routers2.cgi> support this option.

=item B<use lib> <RRDs module path>

If your Perl RRDs module is installed in a location that Perl cannot find by
default, add the module path in this statement to tell Perl where RRDs is.

=back

=head3 Windows specific settings

=over 3

=item B<$SAVEDLOGDIR>

If this script is run on a Windows server, then it will save the status in 
a log file to be picked up by BBNT.  This value should set to the "Saved Logs 
Location" in bbntcfg.exe of the installed BBNT client on that server.

=item B<$BBNTSLEEP>

This value should be be greater than the "logs timer" value in C<bbntcfg.exe> on
the Windows server.  Set "logs timer" very low (like 1) to give time to BBNT to
pick up the status log before the next MRTG entry is put into the logs directory.
Make sure that the "timer" value is high enough to let this script write 
all logs (e.g., 20 entries in mrtg.cfg * 2 seconds = 40 seconds). 

A suggested setting is to put:

    Logs Timer = 1 (bbntcfg.exe)
    B<$BBNTSLEEP> = 2 (this script)

bbmrtg.pl will then create one status log every 2 seconds (B<$BBNTSLEEP>), while
BBNT will pickup each status log in B<$SAVEDDIRLOG> ever 1 second.

This additional seeting is required due to the fact that BBNT can only deal with
one host status log per service (i.e. mrtg). So we let BBNT pick up each new 
service log every "logs timer" while we create them at a lower interval (at 
B<$BBNTSLEEP> interval).  bbmrtg.pl must create a status log file "mrtg" (if 
default is kept).  As you can note, if bbmrtg.pl has multiple status to report, 
it cannot create all of them at once, it must create a single "mrtg" file at a 
time thus the requirement to have BBNT pick the "mrtg" file than bbmrtg.pl can 
create it.

=back

=head2 Configuration

There are two types of configuration lines in the MRTG config file,
global and per-interface.  At this time, the script does not use any
global information.

=over 3

=item B<bb*host[ezwf]:> <hostname>

Required for each target that you want BB to watch. <hostname> is the host 
name as defined as in your etc/bb-hosts file, and defines the host beside which
the status for this target will be displayed in Hobbit / Big Brother.

If you put the same routername on multiple lines then all targets defined for
that hostname will be saved under a single status. Make sure MAXLINE is defined 
in bb.h to be large enough to receive a message with multiple interfaces.

There's a check for the host name containing C|<| or C|>|.  If it does, you will
see a warning that the name seems to contain HTML.  This error can sometimes 
appear because the B<bb*host[]> line was placed directly after the B<PageTop[]>
line in the MRTG config file.  Play it safe, and put B<bb*host[]> immediately 
after the B<Target[]> line.

=item B<bb*svc[ezwf]:> <service name>

Specifies the column in the BB display for this target. This could be used, for 
example, to differentiate serial and ethernet ports on a router.  The default 
value is C<mrtg>.

=item B<bb*althost[ezwf]:> <hostname>

The name of a second host to display the target's status with.  An example
is to list the hostname the interface is connected.  The interface status
will then appear next to that host in the BB display, under the column 
defined below.

=item B<bb*altsvc[ezwf]:> <service name>

Specifies the column in the BB display that this interface will display
under on the alternate host.  The default value is 'mrtg'.

=item B<bb*yellow[ezwf]:> <value>

=item B<bb*red[ezwf]:> <value>

Specifies the thresholds used to determine if an interface should trigger a 
yellow or red status. Each value may take any of three different formats:

=over 4
=item MAX

Warning/panic levels are checked only against a maximum value.

=item MIN:MAX

Warning/panic levels are checked against minimun and maximum values.

=item INMIN:INMAX:OUTMIN:OUTMAX

Warning/panic levels are checked against minimun and maximum values
for both incoming and outgoing channels.

=back

Values can be absolute or a percentage: i.e. 10000 or 85%
A percentage indicates a threshold relative to the 'MaxBytes1' and
'MaxBytes2' value specified for the interface in the MRTG config file;
if no value is specified the default for MaxBytes1 and MaxBytes2
is MaxBytes.  If MaxBytes is not specified the default MaxBytes is 64000.
The default values depend on whether the script thinks that
the interface is an ethernet port.
If it is, the defaults are 40% for yellow and 60% for red.
Otherwise, the defaults are 70% for yellow and 85% for red.

Here's some examples:

   bb*yellow[router_Se0]: 24000
   bb*red[router_Se0]: 32000

   0-23999 for incoming/outgoing generates a green
   24000-31999 for incoming/outgoing generates a yellow
   32000 and + for incoming.outgoing generates a red

   bb*yellow[router_Se1]: 750:24000
   bb*red[router_Se1]: 500:32000

   0-499 for incoming/outgoing generates a red
   500-749 for incoming/outgoing generates a yellow
   750-23999 for incoming/outgoing generates a green
   24000-31999 for incoming/outgoing generates a yellow
   32000 and + for incoming/outgoing generates a red

   bb*yellow[router_Se2]: 750:24000:700:24500
   bb*red[router_Se2]: 500:32000:550:32500

   0-499 for incoming generates a red
   500-749 for incoming generates a yellow
   750-23999 for incoming generates a green
   24000-31999 for incoming generates a yellow
   32000 and + for incoming generates a red

   0-549 for outgoing generates a red
   550-699 for outgoing generates a yellow
   700-24499 for outgoing generates a green
   24500-32499 for outgoing generates a yellow
   32500 and + for outgoing generates a red


=item B<bb*unit[ezwf]:> <unit>

Specifies the units used by MRTG for the target.  You may want to change this 
if MRTG is watching, say, CPU utilization. The default value is 'bytes/sec'.

If <unit> is defined as kb, mb, gb, or tb (kilo -> tera bytes), then BBMRTG will
convert the text below the graph to the appropriate range as well.  This assumes
all data is being stored by MRTG in bytes/sec, so one should be careful with 
this value.

Use B<Factor[]> to adjust the stored values to their proper values if need be.
As an example, there are some devices that apparently report in kbytes 
instead of bytes, so a factor of 1024 would adjust the stored values to bytes.
Any conversion by B<bb*unit[]> would then work properly.

=item B<LegendI[ezwf]:> <label>

=item B<LegendO[ezwf]:> <label>

=item B<bb*in[ezwf]:> <label>

=item B<bb*out[ezwf]:> <label>

Specifies the label used to identify the two values tracked by MRTG.
You may want to change this if MRTG is watching, say, CPU utilization.
The default values are 'In' and 'Out'.
LegendI and LegendO override these; bb*in and bb*out override LegendI and 
LegendO.

If one value defined as '', then the text will only report on the other value.
This can be used when reporting on CPU usage, or some other value for which the
default "In" and "Out" model does not fit.

=back

=head2 Using cfgmaker templates

Later versions of MRTG's cfgmaker utility supports the use of templates
that simplify the creation of bbmrtg.pl ready configuration files.  The 
following example can be used to create such a config file in one step.

=head3 template file

  #
  # Template for use with bbmrtg.pl script (integrates MRTG output into 
  # BigBrother)

  # define how many interfaces are grouped into a column in Hobbit / Big Brother:
  my $bbgroup=8;

  # name the column in BB
  my $bbintgrp=int($ifindex/$bbgroup);
  my $bbsvc=sprintf("int%02d-%02d",
                    int($ifindex/$bbgroup)*$bbgroup+1,
                    (int($ifindex/$bbgroup)+1)*$bbgroup
                   );

  $target_lines .= <<ECHO;
  $default_target_directive
  # bb* = Hobbit / Big Brother info
  bb*host[$target_name]: $$router_ref{routername}
  bb*svc[$target_name]: $bbsvc
  bb*unit[$target_name]: bytes/sec
  ECHO
  if ($if_snmp_alias) {
      $target_lines .= <<ECHO;
  bb*althost[$target_name]: $if_snmp_alias
  bb*altsvc[$target_name]: traffic
  ECHO
  }
  #$default_setenv_directive
  my $setEnvLine = ($if_snmp_alias) ?
                   "SetEnv[$target_name]: MRTG_INT_IP=\"$if_ip\"".
                   " MRTG_INT_DESCR=\"Interface to $if_snmp_alias\"" :
                   "SetEnv[$target_name]: MRTG_INT_IP=\"$if_ip\"".
                   " MRTG_INT_DESCR=\"$if_snmp_descr\"";
  $target_lines .= <<ECHO;
  $setEnvLine
  $default_directory_directive
  $default_maxbytes_directive
  $default_title_directive
  $default_pagetop_directive
  ECHO

=head3 cfgmaker command

After creating the above template, run cfgmaker as follows:

  cfgmaker --if-template=<template_name> host -output host.cfg

=head2 Testing

The script provides "reasonable" defaults for the few BB environment
variables that it needs.  These defaults are to facilate testing, thus
the default value for BB is "/bin/echo".  This means that you can run
the script from the command line until it works, then move it unchanged
into production.

=head1 AUTHOR

BBMRTG was originally adapted from bbmrtg.sh, version 4.5 by Sam Denton.  The
script is currently maintained by Al Payne (apayne@pleiades.com).

Chris Blank, Craig Cook, Robert-Andre Croteau, Sam Denton, Jim Johnson, 
Dan McDonald, Al Payne, and Thomas Ruecker have contributed to BBMRTG.

=head1 SEE ALSO

See L<http://www.pleiades.com/mrtgbb/index.html> for more information on using 
this script.

=head1 DIAGNOSTICS

Running the script manually will display the HTML output on stdout.
Set the TRON environment variable to display debug information.

=head1 BUGS

There is a report of a problem with BBMRTG throwing an error if B<$SHOWGRAPH> is
set to anything less than C<always>.  I can't replicate the error, so more 
information is needed on this before it can be fixed.

Bug reports can be sent to apayne@pleiades.com.  Please include the name of the
script in the message subject or your message by end up in a spam bucket.



