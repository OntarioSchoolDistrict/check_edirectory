## Integration with Monitoring Systems

To use this plugin with Nagios, Icinga, or compatible monitoring systems, add a command definition similar to:

	define command{
		command_name    check_edirectory
		command_line    /usr/bin/perl /path/to/check_edirectory.pl
	}

Then add a service definition referencing this command for your eDirectory host(s).

For Icinga2, use an object CheckCommand and Service definition referencing the script.

Adjust the path and any required options (such as --timeout or --verbose) as needed.

## Example --help Output


Running the plugin with --help or -h will display:

		check_edirectory v0.1 - Nagios Plugin
		Checks eDirectory health using ndsrepair and ndsstat.

		Options:
			-h, --help         Show this help message
			-V, --version      Show version
			-t, --timeout      Plugin timeout in seconds (default: 10)
			-v, --verbose      Increase verbosity
			-d, --debug        Print the command(s) that would be executed, but do not run them
			-T                Only check Time Status
			-E                Only check Synchronization Status
			-P                Only check Replica and Partition Status

		If none of -T, -E, -P are given, the script prints help and does not run any checks. At least one check option must be specified.

# check_edirectory
Monitoring plugin to check eDirectory using ndsrepair.



This Perl script runs `ndsrepair` and `ndsstat` with the following tests and parses their results:

- `-T` Time Status (ndsrepair): Checks for time synchronization errors.
- `-E` Synchronization Status (ndsrepair): Checks for partition synchronization errors and error codes.
- `-P` Replica and Partition Status (ndsstat): Checks that all replicas are in the "On" state. Only actual replica entry lines (starting with `.CN=`) are parsed, and headers/partitions are ignored. If any replica is not "On", the plugin reports CRITICAL and lists the states.


## Usage

		perl check_edirectory.pl [options]

Options:
	-h, --help         Show help
	-V, --version      Show version
	-t, --timeout      Plugin timeout in seconds (default: 10)
	-v, --verbose      Increase verbosity
	-d, --debug        Print the command(s) that would be executed, but do not run them
	-T                 Only check Time Status
	-E                 Only check Synchronization Status
	-P                 Only check Replica and Partition Status

If none of -T, -E, -P are given, the script prints help and does not run any checks. At least one check option must be specified.

## Output

- OK: All checks passed
- WARNING: Non-critical issues detected (e.g., warning codes, sync lag)
- CRITICAL: Errors or replicas not "On"
- UNKNOWN: Output could not be parsed or command failed

For the -P check, the plugin now only considers lines that start with `.CN=` as replica entries, ensuring accurate detection of replica states.

## Debug Option

When the `-d` or `--debug` option is specified, the plugin will print the exact command(s) that would be executed for each selected check, but will not actually run them. This is useful for verifying configuration and command construction without affecting the system.


## Requirements
- Perl
- eDirectory with `ndsrepair` and `ndsstat` available (see below for configuration)

## Configuration

At the top of the script, the paths to `ndsrepair` and `ndsstat` are set as variables for easy customization:

	my $ndsrepair = '/usr/bin/ndsrepair';
	my $ndsstat   = '/opt/novell/eDirectory/bin/ndsstat';

If your eDirectory installation uses a custom configuration file (e.g., for a non-default instance or user), you can add the `--config-file` option to these variables. For example:

	my $ndsrepair = '/usr/bin/ndsrepair --config-file /home/nds-user/etc/nds.conf';
	my $ndsstat   = '/opt/novell/eDirectory/bin/ndsstat --config-file /home/nds-user/etc/nds.conf';

Edit these variables at the top of the script to match your environment.
