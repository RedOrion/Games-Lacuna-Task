# ============================================================================
package Games::Lacuna::Task;
# ============================================================================

use 5.010;
use version;
our $AUTHORITY = 'cpan:MAROS';
our $VERSION = version->new("1.00");

use Games::Lacuna::Task::Types;

use Moose;
use Try::Tiny;
use YAML qw(LoadFile);

use Module::Pluggable 
    search_path => ['Games::Lacuna::Task::Action'],
    sub_name => 'all_tasks';

with qw(Games::Lacuna::Task::Role::Client
    Games::Lacuna::Task::Role::Helper
    Games::Lacuna::Task::Role::Logger
    MooseX::Getopt);

has 'task'  => (
    is              => 'ro',
    isa             => 'ArrayRef[Str]',
    required        => 1,
    documentation   => 'Select whick tasks to run [Reqired, Multiple]',
);

has '+database' => (
    required        => 1,
);

our $WIDTH = 62;

sub run {
    my ($self) = @_;
    
    my $client = $self->client();
    
    # Call lazy builder
    $client->client;
    
    my $empire_name = $self->lookup_cache('config')->{name};
    
    $self->log('notice',("=" x $WIDTH));
    $self->log('notice',"Running tasks for empire %s",$empire_name);
    
    my $database_dir = $self->database->dir;
    
    my @tasks;
    if (scalar @{$self->task} == 1
        && lc($self->task->[0]) eq 'all') {
        @tasks = __PACKAGE__->all_tasks;
    } else {
        foreach my $task (@{$self->task}) {
            my $element = join('',map { ucfirst(lc($_)) } split(/_/,$task));
            my $class = 'Games::Lacuna::Task::Action::'.$element;
            push(@tasks,$class)
                unless $class ~~ \@tasks;
        }
    }
    
    # Loop all tasks
    TASK:
    foreach my $task_class (@tasks) {
        my $task_name = $task_class;
        $task_name =~ s/^.+::([^:]+)$/$1/;
        $task_name = lc($task_name);
        
        $self->log('notice',("-" x $WIDTH));
        $self->log('notice',"Running task %s",$task_name);
        
        # Get task config
        my $task_config = {};
        my $task_config_file = Path::Class::File->new($database_dir,$task_name.'.yml');
        if (-e $task_config_file) {
            $self->log('debug',"Loading task %s config from",$task_name,$task_config_file);
            $task_config = LoadFile($task_config_file->stringify);
        }
        
        my $ok = 1;
        try {
            Class::MOP::load_class($task_class);
        } catch {
            $self->log('error',"Could not load task %s: %s",$task_class,$_);
            $ok = 0;
        };
        if ($ok) {
            try {
                my $task = $task_class->new(
                    %{$task_config},
                    client  => $client,
                    loglevel=> $self->loglevel,
                );
                $task->run;
            } catch {
                $self->log('error',"An error occured while processing %s: %s",$task_class,$_);
            }
        }
    }
    $self->log('notice',("=" x $WIDTH));
}

1;