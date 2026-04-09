#!/usr/bin/env perl

use strict;
use warnings;
use lib "/usr/local/nagios/libexec";
use Getopt::Long;

# Top-level option and state variables
my $ndsrepair = '/opt/novell/eDirectory/bin/ndsrepair';
my $ndsstat   = '/opt/novell/eDirectory/bin/ndsstat';
my $help = 0;
my $version = 0;
my $timeout = 10;
my $verbose = 0;
my $opt_T = 0;
my $opt_E = 0;
my $opt_P = 0;
my $debug = 0;
our %ERRORS = (
    'OK'       => 0,
    'WARNING'  => 1,
    'CRITICAL' => 2,
    'UNKNOWN'  => 3,
);
my @all_tests = (
    { flag => '-T', name => 'Time Status' },
    { flag => '-E', name => 'Synchronization Status' },
    { flag => '-P', name => 'Replica and Partition Status' },
);
my @tests;

my $args_given = @ARGV ? 1 : 0;

sub print_help {
    print "\ncheck_edirectory v0.1 - Nagios Plugin\n";
    print "Checks eDirectory health using ndsrepair and ndsstat.\n";
    print "\nOptions:\n";
    print "  -h, --help         Show this help message\n";
    print "  -V, --version      Show version\n";
    print "  -t, --timeout      Plugin timeout in seconds (default: 10)\n";
    print "  -v, --verbose      Increase verbosity\n";
    print "  -d, --debug        Print the command(s) that would be executed, but do not run them\n";
    print "  -T                Only check Time Status\n";
    print "  -E                Only check Synchronization Status\n";
    print "  -P                Only check Replica and Partition Status\n";
    print "\nIf none of -T, -E, -P are given, the script prints help and does not run any checks.\n";
    print "At least one check option must be specified.\n";
}

sub print_version {
    print "check_edirectory version 0.1\n";
}

Getopt::Long::Configure('no_ignore_case');
GetOptions(
    'help|h'     => \$help,
    'version|V'  => \$version,
    'timeout|t=i'=> \$timeout,
    'verbose|v+' => \$verbose,
    'debug|d'    => \$debug,
    'T'          => \$opt_T,
    'E'          => \$opt_E,
    'P'          => \$opt_P,
) or do {
    print_help();
    exit $ERRORS{'UNKNOWN'};
};

if ($help) {
    print_help();
    exit $ERRORS{'OK'};
}
if ($version) {
    print_version();
    exit $ERRORS{'OK'};
}

# If no arguments are given, print usage and exit UNKNOWN (Nagios standard)
if (!$args_given) {
    print_help();
    exit $ERRORS{'UNKNOWN'};
}

if ($opt_T || $opt_E || $opt_P) {
    push @tests, grep { ($opt_T && $_->{flag} eq '-T') || ($opt_E && $_->{flag} eq '-E') || ($opt_P && $_->{flag} eq '-P') } @all_tests;
}

if (!@tests) {
    print_help();
    exit $ERRORS{'UNKNOWN'};
}

eval {
    local $SIG{ALRM} = sub { die "Timeout\n" };
    alarm $timeout;

    my $status = $ERRORS{'OK'};
    my @messages;
    my @perfdata;
    my @verbose_output;

    foreach my $test (@tests) {
        my $flag = $test->{flag};
        my $name = $test->{name};

        if ($flag eq '-T') {
            my $command = "$ndsrepair $flag 2>&1";
            if ($debug) {
                print "DEBUG: Running command: $command\n";
                return;
            } else {
                my $output = `$command` // '';
                my ($t_total_errors) = $output =~ /^\s*Total errors:\s*(\d+)/m;
                if (!defined $t_total_errors) {
                    push @messages, "$name: UNKNOWN (could not parse output)";
                    $status = $ERRORS{'UNKNOWN'} if $status < $ERRORS{'UNKNOWN'};
                } else {
                    my @t_not_in_sync = $output =~ /^\S+\s+\d+\.\d+\s+\d+\s+\S+\s+(No)\s+/mg;
                    my @t_error_lines = $output =~ /^(ERROR: .*)$/mg;
                    if ($t_total_errors == 0 && !@t_not_in_sync && !@t_error_lines) {
                        push @messages, "$name: OK";
                    } else {
                        my $err_msg = '';
                        $err_msg .= ' Not in sync.' if @t_not_in_sync;
                        $err_msg .= ' ' . join(' ', @t_error_lines) if @t_error_lines;
                        push @messages, "$name: CRITICAL$err_msg";
                        $status = $ERRORS{'CRITICAL'};
                    }
                    push @perfdata, "'ndsrepair_T_total_errors'=$t_total_errors;0;1;0;";
                }
                if ($verbose) {
                    push @verbose_output, "[$name]\n$output";
                }
            }

        } elsif ($flag eq '-E') {
            my $command = "$ndsrepair $flag 2>&1";
            if ($debug) {
                print "DEBUG: Running command: $command\n";
                return;
            } else {
                my $output = `$command` // '';
                my ($e_total_errors) = $output =~ /^\s*Total errors:\s*(\d+)/m;
                if (!defined $e_total_errors) {
                    push @messages, "$name: UNKNOWN (could not parse output)";
                    $status = $ERRORS{'UNKNOWN'} if $status < $ERRORS{'UNKNOWN'};
                } else {
                    my $e_all_synced = ($output =~ /All servers synchronized/i) ? 1 : 0;
                    my @e_error_lines = $output =~ /^(ERROR: .*)$/mg;
                    my @e_sync_lag_lines = $output =~ /(\*{10} \*{8,} *-?\d+)/g;
                    my @e_warn_codes = ($output =~ /\s(-663|-774)\b/g);
                    my @e_other_neg_codes = ($output =~ /\s-(?!663\b|774\b)(\d+)\b/g);
                    if ($e_total_errors == 0 && $e_all_synced && !@e_error_lines && !@e_sync_lag_lines && !@e_warn_codes && !@e_other_neg_codes) {
                        push @messages, "$name: OK";
                    } elsif (@e_error_lines || @e_other_neg_codes) {
                        my $err_msg = '';
                        $err_msg .= ' ' . join(' ', @e_error_lines) if @e_error_lines;
                        $err_msg .= ' Negative error codes: ' . join(',', @e_other_neg_codes) if @e_other_neg_codes;
                        push @messages, "$name: CRITICAL$err_msg";
                        $status = $ERRORS{'CRITICAL'};
                    } elsif (@e_warn_codes || @e_sync_lag_lines || $e_total_errors > 0) {
                        my $warn_msg = '';
                        $warn_msg .= ' Warning codes: ' . join(',', @e_warn_codes) if @e_warn_codes;
                        $warn_msg .= ' Sync lag detected.' if @e_sync_lag_lines;
                        $warn_msg .= " Total errors: $e_total_errors." if $e_total_errors > 0;
                        push @messages, "$name: WARNING$warn_msg";
                        $status = $ERRORS{'WARNING'} if $status < $ERRORS{'WARNING'};
                    } else {
                        push @messages, "$name: UNKNOWN (unhandled state)";
                        $status = $ERRORS{'UNKNOWN'} if $status < $ERRORS{'UNKNOWN'};
                    }
                    push @perfdata, "'ndsrepair_E_total_errors'=$e_total_errors;0;1;0;";
                }
                if ($verbose) {
                    push @verbose_output, "[$name]\n$output";
                }
            }
        } elsif ($flag eq '-P') {
            my $command = "$ndsstat -r 2>&1";
            if ($debug) {
                print "DEBUG: Running command: $command\n";
                return;
            } else {
                my $stat_output = `$command` // '';
                if ($? != 0) {
                    push @messages, "$name: ndsstat failed";
                    $status = $ERRORS{'CRITICAL'};
                    next;
                }
                # Only match lines that look like actual replica entries (start with .CN= and have columns)
                my @replica_states;
                foreach my $line (split /\n/, $stat_output) {
                    if ($line =~ /^\.CN=[^\s]+\s+\S+\s+(\S+)/) {
                        push @replica_states, $1;
                    }
                }
                my @not_on = grep { $_ ne 'On' } @replica_states;
                if (@not_on) {
                    push @messages, "$name: CRITICAL - Replica(s) not On: " . join(',', @not_on);
                    $status = $ERRORS{'CRITICAL'};
                } else {
                    push @messages, "$name: OK";
                }
                push @perfdata, "'ndsstat_P_not_on'=" . scalar(@not_on) . ";0;1;0;";
                if ($verbose) {
                    push @verbose_output, "[$name]\n$stat_output";
                }
            }
        }
    }

    alarm 0;
    my $summary = join(", ", grep { !/^\s*$/ } @messages);
    my $perf = @perfdata ? " | " . join(" ", @perfdata) : '';
    print "$summary$perf\n";
    if ($verbose && @verbose_output) {
        print join("\n", @verbose_output) . "\n";
    }
    exit $status;
};
if ($@) {
    if ($@ =~ /Timeout/) {
        print "CRITICAL - Plugin timed out after $timeout seconds\n";
        exit $ERRORS{'CRITICAL'};
    } else {
        print "UNKNOWN - $@\n";
        exit $ERRORS{'UNKNOWN'};
    }
}
