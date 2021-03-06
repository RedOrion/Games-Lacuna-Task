package Games::Lacuna::Task::Action::Astronomy;

use 5.010;

use Moose;
extends qw(Games::Lacuna::Task::Action);
with qw(Games::Lacuna::Task::Role::Stars
    Games::Lacuna::Task::Role::Ships);

sub description {
    return q[This task automates probing of stars];
}

before 'run' => sub {
    my $self = shift;
    $self->check_for_destroyed_probes();
};

sub process_planet {
    my ($self,$planet_stats) = @_;
        
    # Get observatory
    my $observatory = $self->find_building($planet_stats->{id},'Observatory');
    
    # Get space port
    my $spaceport = $self->find_building($planet_stats->{id},'SpacePort');
    
    return 
        unless $observatory && $spaceport;
    
    # Max probes controllable
    my $max_probes = $observatory->{level} * 3;
    
    # Get observatory probed stars
    my $observatory_object = $self->build_object($observatory);
    my $observatory_data = $self->request(
        object  => $observatory_object,
        method  => 'get_probed_stars',
        params  => [1],
    );
    
    my $can_send_probes = $max_probes - $observatory_data->{star_count};
    
    # Reached max probed stars
    return
        if $can_send_probes == 0;
    
    # Get available probes
    my @avaliable_probes = $self->ships(
        planet          => $planet_stats,
        ships_needed    => $can_send_probes,
        ship_type       => 'probe',
        ships_travelling=> 1,
    );
    
    return 
        if (scalar @avaliable_probes == 0);
    
    my $spaceport_object = $self->build_object($spaceport);
    
    # Get unprobed stars
    my @unprobed_stars = $self->closest_unprobed_stars($planet_stats->{x},$planet_stats->{y},scalar(@avaliable_probes));
    
    # Send available probes to stars
    foreach my $star (@unprobed_stars) {
        my $probe = pop(@avaliable_probes);
        if (defined $probe) {
            
            # Send probe to star
            my $response = $self->request(
                object  => $spaceport_object,
                method  => 'send_ship',
                params  => [ $probe,{ "star_id" => $star } ],
            );
            
            $self->log('notice',"Sending probe from from %s to %s",$planet_stats->{name},$response->{ship}{to}{name});
        }
    }
}

sub check_for_destroyed_probes {
    my ($self) = @_;
    
    my $inbox_object = $self->build_object('Inbox');
    
    # Get inbox
    my $inbox_data = $self->request(
        object  => $inbox_object,
        method  => 'view_inbox',
        params  => [{ tags => 'Alert',page_number => 1 }],
    );
    
    my @archive_messages;
    
    foreach my $message (@{$inbox_data->{messages}}) {
        next
            unless $message->{from_id} == $message->{to_id};
        
        given ($message->{subject}) {
            when('Probe Detected!') {
                push(@archive_messages,$message->{id});
            }
            when ('Probe Destroyed') {
                
                # TODO check last run so that we do not process old messages
                #$self->parse_date($message->{date});
                
                # Get message
                my $message_data = $self->request(
                    object  => $inbox_object,
                    method  => 'read_message',
                    params  => [$message->{id}],
                );
                
                # Parse star id,x,y
                next
                    unless $message_data->{message}{body} =~ m/{Starmap\s(?<x>-*\d+)\s(?<y>-*\d+)\s(?<star_name>[^}]+)}/;
                
                my $star_name = $+{star_name};
                my $star_id = $self->find_star_by_xy($+{x},$+{y});
                
                next
                    unless $star_id;
                next
                    unless $message_data->{message}{body} =~ m/{Empire\s(?<empire_id>\d+)\s(?<empire_name>[^}]+)}/;
                
                # Get star data from api and check if solar system is probed
                $self->check_star($star_id);
                
                $self->log('warn','A probe in the %s system was shot down by %s',$star_name,$+{empire_name});
                
                push(@archive_messages,$message->{id});
            }
        }
    }
    
    # Archive
    if (scalar @archive_messages) {
        $self->log('notice',"Archiving %i messages",scalar @archive_messages);
        
        $self->request(
            object  => $inbox_object,
            method  => 'archive_messages',
            params  => [\@archive_messages],
        );
    }
}

sub closest_unprobed_stars {
    my ($self,$x,$y,$limit) = @_;
    
    $limit //= 1;
    
    my @unprobed_stars;
    
    STARS:
    foreach my $star ($self->stars_by_distance($x,$y)) {
        
        # Check if star has already been probed
        next STARS
            if $self->is_probed_star($star->{id});
        
        # Check star again (might be probed in the meantime)
        my $star_data = $self->check_star($star->{id});
        
        next STARS
            if defined $star_data->{bodies}
            && scalar @{$star_data->{bodies}} > 0;
        
        # Get incoming probe info
        my $star_incomming = $self->request(
            object  => $self->build_object('Map'),
            params  => [ $star->{id} ],
            method  => 'check_star_for_incoming_probe',
        );
        
        next
            if ($star_incomming->{incoming_probe} > 0);
        
        # Add to todo list
        push(@unprobed_stars,$star->{id});
        
        last STARS
            if scalar(@unprobed_stars) >= $limit;
    }
    
    return @unprobed_stars;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;