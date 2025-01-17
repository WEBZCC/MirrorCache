use utf8;
package MirrorCache::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';
use Mojo::File qw(path);
# use Mojo::Pg;
# use Mojo::mysql;

__PACKAGE__->load_namespaces;

my $SINGLETON;
my $SINGLETONR;

my $PROVIDER = $ENV{MIRRORCACHE_DB_PROVIDER};

$PROVIDER = 'mysql' if !$PROVIDER && $ENV{TEST_MYSQL};

$PROVIDER = 'postgresql' unless $PROVIDER;

$PROVIDER = 'Pg'    if $PROVIDER eq 'postgresql';
$PROVIDER = 'mysql' if $PROVIDER eq 'mariadb';

sub pg {
    return 1 if $PROVIDER eq 'Pg';
    return 0;
}

sub provider {
    return $PROVIDER;
}

sub connect_db {
    my %args  = @_;

    unless ($SINGLETON) {
        if (pg()) {
            require Mojo::Pg;
        } else {
            require 'Mojo/' . $PROVIDER . '.pm';
        }

        my $dsn;
        my $user = $ENV{MIRRORCACHE_DBUSER};
        my $pass = $ENV{MIRRORCACHE_DBPASS};
        if ($ENV{TEST_PG}) {
            $dsn = $ENV{TEST_PG};
        } elsif ($ENV{TEST_MYSQL}) {
            $dsn = $ENV{TEST_MYSQL};
        } elsif ($ENV{MIRRORCACHE_DSN}) {
            $dsn = $ENV{MIRRORCACHE_DSN};
        } else {
            my $db   = $ENV{MIRRORCACHE_DB} // 'mirrorcache';
            my $host = $ENV{MIRRORCACHE_DBHOST};
            my $port = $ENV{MIRRORCACHE_DBPORT};
            $dsn  = "DBI:$PROVIDER:dbname=$db";
            $dsn = "$dsn;host=$host" if $host;
            $dsn = "$dsn;port=$port" if $port;
        }
        $SINGLETON = __PACKAGE__->connect($dsn, $user, $pass);
    }

    return $SINGLETON;
}

sub connect_replica_db {
    my %args  = @_;

    unless ($SINGLETONR) {
        my $dsn;
        my $user = $ENV{MIRRORCACHE_DBUSER};
        my $pass = $ENV{MIRRORCACHE_DBPASS};
        if ($ENV{MIRRORCACHE_DSN_REPLICA}) {
            $dsn = $ENV{MIRRORCACHE_DSN_REPLICA};
        } else {
            my $db   = $ENV{MIRRORCACHE_DB} // 'mirrorcache';
            my $host = $ENV{MIRRORCACHE_DBREPLICA};
            my $port = $ENV{MIRRORCACHE_DBPORT};
            $dsn  = "DBI:$PROVIDER:dbname=$db";
            $dsn = "$dsn;host=$host" if $host;
            $dsn = "$dsn;port=$port" if $port;
        }
        $SINGLETONR = __PACKAGE__->connect($dsn, $user, $pass);
    }

    return $SINGLETONR;
}

sub disconnect_db {
    if ($SINGLETON) {
        $SINGLETON->storage->disconnect;
        $SINGLETON = undef;
    }
    if ($SINGLETONR) {
        $SINGLETONR->storage->disconnect;
        $SINGLETONR = undef;
    }
}

sub dsn {
    my $self = shift;
    my $ci = $self->storage->connect_info->[0];
    if ( $ci eq 'HASH' ) {
        return $ci->{dsn}
    }
    return $ci;
}

sub singleton { $SINGLETON || connect_db() }

sub singletonR {
    return singleton() unless $ENV{MIRRORCACHE_DBREPLICA};

    $SINGLETONR || connect_replica_db();
}

sub has_table {
    my ($self,$table_name) = @_;

    my $sth = $self->storage->dbh->table_info(undef, 'public', $table_name, 'TABLE');
    $sth->execute;
    my @info = $sth->fetchrow_array;

    my $exists = scalar @info;
    return $exists;
}

sub migrate {
    my $self = shift;
    my $conn = "Mojo::$PROVIDER"->new;
    $conn->dsn( $self->dsn );
    $conn->password($ENV{MIRRORCACHE_DBPASS}) if $ENV{MIRRORCACHE_DBPASS};

    my $dbh     = $self->storage->dbh;
    my $dbschema = path(__FILE__)->dirname->child('resources', 'migrations', "$PROVIDER.sql");
    $conn->auto_migrate(1)->migrations->name('mirrorcache')->from_file($dbschema);
    $conn->db; # this will do migration
}

1;
