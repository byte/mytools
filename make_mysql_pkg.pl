#!/usr/bin/perl -w
#
#
# make_mysql_pkg.pl
#
# This script creates a Mac OS X installation package
# of MySQL for Apple's Installer application.
#
# To use it:
#
# 1.) Unpack the mysql source tarball and cd into the directory
# 2.) execute this script
# 
#
# Written by Marc Liyanage (http://www.entropy.ch)
# Updated by Colin Charles (http://bytebot.net/)
#
# History:
#
# When         Who              What
# ------------------------------------------------------------------
# 2001-09-16   Marc Liyanage    First version
# 2001-11-18   Marc Liyanage    Improved configure directory options
# 2010-03-04	Colin Charles	Make it ready for MariaDB

use strict;
use DirHandle;

my $data = {};
	
$data->{PREFIX_DIR}     = "/usr/local/mysql";
$data->{CONFIG}         = join(" ",
	"--prefix=$data->{PREFIX_DIR}",
	"--localstatedir=$data->{PREFIX_DIR}/data",
	"--libdir=$data->{PREFIX_DIR}/lib",
	"--includedir=$data->{PREFIX_DIR}/include",
	"--with-named-z-libs=/usr/local/libz.a",
	"--with-innodb",
	"--with-server-suffix='-mariadb'",
	"--with-comment='http://www.mariadb.com/download'",
	"--with-mysqld-user=mysql",
	"--enable-assembler",
	"CFLAGS=\"-DHAVE_BROKEN_REALPATH -lncurses\"",
);





prepare($data);
configure_source($data);
make($data);
make_binary_distribution($data);
create_pax_root($data);
create_package($data);
cleanup($data);

print "Package $data->{PACKAGE_TARBALL_FILENAME} created\n";






# Subroutines follow here...




# Prepares data in the global $data hash, like version numbers,
# directory names etc. Also makes sure that no old stuff
# is in our way.
# 
sub prepare {

	my ($data) = @_;
	
	# Keep the current wd for reference
	#
	$data->{OLDWD} = `pwd`;
	chomp($data->{OLDWD});

	# Look for configure script
	#
	unless (-f "configure") {
		abort($data, "Unable to find 'configure', make sure you're in the MySQL source toplevel directory!");
	}

	# Try to find version number there
	#
	my $mysql_version_h = `cat configure`;
	($data->{VERSION}) = $mysql_version_h =~ /^VERSION=(.+?)$/m;

	unless ($data->{VERSION} =~ /\d+/) {
		abort($data, "Unable to find MySQL version number!");
	}

	debug($data, "found MySQL version number $data->{VERSION}");
	
	
	# PAXROOT_DIR is where we will build our own little
	# fake /usr/local directory. Make sure it doesn't exist,
	# then try to create it.
	#
	$data->{PAXROOT_DIR} = "/tmp/mysql-$data->{VERSION}-paxroot";

	if (-e $data->{PAXROOT_DIR}) {
		abort($data, "$data->{PAXROOT_DIR} exists, please remove first");
	}

	if (system("mkdir $data->{PAXROOT_DIR}")) {
		abort($data, "Unable to mkdir $data->{PAXROOT_DIR}, please make sure you have the right permissions!");
	}
	

	# PACKAGE_DIR is where we will build the package directory
	# hierarchy, according to the standard .pkg layout.
	#
	$data->{PACKAGE_NAME} = "mysql-$data->{VERSION}.pkg";
	$data->{PACKAGE_DIR} = "/tmp/$data->{PACKAGE_NAME}";

	if (-e $data->{PACKAGE_DIR}) {
		abort($data, "$data->{PACKAGE_DIR} exists, please remove first");
	}

	if (system("mkdir $data->{PACKAGE_DIR}")) {
		abort($data, "Unable to mkdir $data->{PACKAGE_DIR}, please make sure you have the right permissions!");
	}
	
	
}



# Configure the MySQL source with our options
#
sub configure_source {

	my ($data) = @_;

	if (system("./configure $data->{CONFIG}")) {
		abort($data, "Unable to configure!");
	}

}




# Build the software
#
sub make {

	my ($data) = @_;

	if (system("make")) {
		abort($data, "Unable to make!");
	}

}



# We don't ever install the software, but instead we use an
# included script to create a binary distribution
# tarball.
#
sub make_binary_distribution {

	my ($data) = @_;

	if (system("./scripts/make_binary_distribution > make_binary_distribution.out")) {
		abort($data, "Unable to make_binary_distribution!");
	}
	
	my @output = `cat make_binary_distribution.out`;
	my $last_line = $output[-1];
	unlink("make_binary_distribution.out");
	
	my ($tarball_filename, $tarball_directory) = $last_line =~ /^((.+)\.tar\.gz) created/i;

	unless ($tarball_filename and -f $tarball_filename) {
		abort($data, "Unable determine the output filename of scripts/make_binary_distribution!");
	}
	
	$data->{BINARY_TARBALL_FILENAME} = $tarball_filename;
	$data->{BINARY_TARBALL_DIRECTORY} = $tarball_directory;

}




# Now we build a fake /usr/local directory hierarchy.
# This will be fed to the pax tool to create the archive.
#
sub create_pax_root {

	my ($data) = @_;

	# Go there and try to extract the binary distribution
	# tarball which we created in the previous step.
	#
	chdir($data->{PAXROOT_DIR});
	my $tarfile = "$data->{OLDWD}/$data->{BINARY_TARBALL_FILENAME}";
	
	if (system("tar -xzf $tarfile")) {
		abort($data, "Unable to extract $tarfile inside $data->{PAXROOT_DIR}");
	}
	
	# Rename it to what we want it to be in the
	# installed /usr/local directory later on, i.e.
	# mysql-<version>. Then create a symlink from
	# mysql to mysql-<version>
	#
	rename($data->{BINARY_TARBALL_DIRECTORY}, "mysql-$data->{VERSION}");
	symlink("mysql-$data->{VERSION}", "mysql");


	# We create a bunch of symlinks in /usr/local/bin and
	# /usr/local/share/man so that the end-user will not
	# have to adjust PATH and MANPATH to include the
	# /usr/local/mysql/bin and man directories.
	#
	system("mkdir -p $_") foreach qw(bin share/man);


	# First create the symlinks in the bin directory
	#
	# 2001-02-13: we no longer use symlinks for the binaries, we
	# use small dummy scripts instead because the
	# mysql scripts do a lot of guesswork with their
	# own path and that will not work when called via the symlink
	#
#	symlink("../mysql/bin/$_", "$_") foreach (grep {$_ !~ /^\.+$/} DirHandle->new("../mysql/bin")->read());

	chdir("bin");

	foreach my $command (grep {$_ !~ /^\.+$/} DirHandle->new("../mysql/bin")->read()) {
		
		my $scriptcode = qq+#!/bin/sh\n# Part of the entropy.ch mysql package\ncd /usr/local/mysql/\nexec ./bin/$command "\$\@"\n+;
		open(SCRIPTFILE, ">$command") or die "Unable to write open $command\n";
		print SCRIPTFILE $scriptcode;
		close(SCRIPTFILE);
		chmod(0755, $command);
		
	}







	# Now include the man pages. Two problems here:
	# 1.) the make_binary_distribution script does not seem
	#     to include the man pages, so we have to copy them over
	#     now. [outdated, was fixed by MySQL!]
	# 2.) The man pages could be in different sections, so
	#     we have to recursively copy *and* symlink them.
	#

	# First find out what's there in the source distribution.
	# Store the names of the manpages in anonymous
	# arrays which in turn will be stored in a hash, using
	# the section numbers as hash keys.
	#
	chdir("$data->{PAXROOT_DIR}/mysql");
	my %man_sections;
	foreach my $manpage (grep {$_ =~ /^.+\.(\d+)$/} DirHandle->new("man")->read()) {

		my ($section) = $manpage =~ /\.(\d+)$/;

		$man_sections{$section} ||= [];
		push @{$man_sections{$section}}, "$manpage";

	}


	# Now iterate through the sections and man pages,
	# and copy/symlink the man pages
	#
	chdir("$data->{PAXROOT_DIR}/share/man/");

	foreach my $section (keys(%man_sections)) {
		
		system("mkdir -p man$section");
		chdir("man$section");
		
		foreach my $manpage (@{$man_sections{$section}}) {
			
			symlink("../../../mysql/man/$manpage", $manpage)
						
		}

		chdir("..");
		
	}
}



# Take the pax root directory, create a few auxiliary
# files and then pack everything up into a tarball
#
sub create_package {

	my ($data) = @_;

	# Create the resources directory in which all
	# interesting files for this package will be stored
	#
	$data->{PKG_RESOURCES_DIR} = "$data->{PACKAGE_DIR}/Contents/Resources";

	if (system("mkdir -p $data->{PKG_RESOURCES_DIR}")) {
		abort("Unable to create package resources dir $data->{PKG_RESOURCES_DIR}");
	}


	# Create the big archive with all the files using
	# the pax tool
	#
	chdir($data->{PAXROOT_DIR});
	if(system("pax -w . | gzip -c > $data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.pax.gz")) {
		abort("Unable to create package pax file");
	}


	# Create the "Bill Of Materials" (bom) file.
	#	
	if(system("mkbom . $data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.bom")) {
		abort("Unable to create package bom file");
	}


	# Create the ".sizes" file with some information about the package
	#	
	my $size_uncompressed = `du -sk $data->{PAXROOT_DIR} | cut -f 1`;
	chomp($size_uncompressed);
	
	my $size_compressed = `du -sk $data->{PACKAGE_DIR} | cut -f 1`;
	chomp($size_compressed);
	
	my $numfiles = `find /tmp/mysql-$data->{VERSION}-paxroot | wc -l`;
	$numfiles--;
	
	open(SIZESFILE, ">$data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.sizes") or abort("Unable to write open sizes file $data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.sizes");
	print SIZESFILE "NumFiles $numfiles\n";
	print SIZESFILE "InstalledSize $size_uncompressed\n";
	print SIZESFILE "CompressedSize $size_compressed\n";
	close(SIZESFILE);


	# Create the ".info" file with more information abou the package.
	#
	open(INFOFILE, ">$data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.info") or abort("Unable to write open sizes file $data->{PKG_RESOURCES_DIR}/mysql-$data->{VERSION}.info");
	my $infodata = join("", <DATA>);
	$infodata =~ s/<%(.+?)%>/$data->{$1}/eg;
	abort("Unable to get info file data from __DATA__!") unless ($infodata =~ /\w+/);
	print INFOFILE $infodata;
	close(INFOFILE);



	# Finally, create the .tar.gz file for the package, 
	# this is our end result
	#
	chdir($data->{PACKAGE_DIR});
	chdir("..");
	
	$data->{PACKAGE_TARBALL_FILENAME} = "$data->{PACKAGE_NAME}.tar.gz";

	if(system("tar -czf $data->{OLDWD}/$data->{PACKAGE_TARBALL_FILENAME} $data->{PACKAGE_NAME}")) {
		abort("Unable to create package tar file $data->{OLDWD}/$data->{PACKAGE_TARBALL_FILENAME}");
	}

	
	
}


# Abort with an error message
#
sub abort {

	my ($data, $errormessage) = @_;
	
	my ($caller) = (caller(1))[3];
	$caller =~ s/^main:://;
	
	print "*** Error: $caller(): $errormessage\n";
	
	exit 1;

}


# Output informative messages
#
sub debug {

	my ($data, $message) = @_;
	
	my ($caller) = (caller(1))[3];
	$caller =~ s/^main:://;
	
	print "*** Info: $caller(): $message\n";

}



# Remove temporary items
#
sub cleanup {

	my ($data) = @_;
	
	chdir($data->{OLDWD});
	
	system("rm -rf $data->{PACKAGE_DIR}");
	system("rm -rf $data->{PAXROOT_DIR}");
	system("rm $data->{BINARY_TARBALL_FILENAME}");

}




__DATA__
Title MariaDB
Version <%VERSION%>
Description The MariaDB database is a new branch of the MySQL database which includes all major open source storage engines, myriad bug fixes, and many community patches. Find out more at http://www.mariadb.com/.
DefaultLocation /usr/local
Diskname (null)
DeleteWarning
NeedsAuthorization YES
DisableStop NO
UseUserMask NO
Application NO
Relocatable NO
Required NO
InstallOnly NO
RequiresReboot NO
InstallFat NO
