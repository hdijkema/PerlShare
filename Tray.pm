package Tray;
use Gtk2;

sub new() {
	my $class = shift;
	my $img_dir = shift;
	my $menu = shift;
	my $kind = shift;

	my $obj={};
	
	$obj->{img_dir} = $img_dir;
	$obj->{popup_menu} = $menu;

	# Create pixbufs 
	for my $i qw(0 1 2 3 4 5 6 7 8) {
		$obj->{"icn_active_$i"}=Gtk2::Gdk::Pixbuf->new_from_file("$img_dir/tray_active_$i.png");
	}
	$obj->{"icn_inactive"}=Gtk2::Gdk::Pixbuf->new_from_file("$img_dir/tray_inactive.png");
	
	for my $i qw(0 1 2 3 4 5 6 7 8) {
		$obj->{"icn_collision_$i"}=Gtk2::Gdk::Pixbuf->new_from_file("$img_dir/tray_collision_$i.png");
	}
	$obj->{"icn_collision"}=Gtk2::Gdk::Pixbuf->new_from_file("$img_dir/tray_collision.png");
	
	my $use_statusicon = 1;
	my $use_appindicator = 0;
	if ($kind eq "appindicator") {
	  $use_statusicon = 0;
	  $use_appindicator = 1;
	}

	if ($use_statusicon) {
		my $status_icon=Gtk2::StatusIcon->new_from_pixbuf($obj->{icn_inactive});
		my $os=$^O;
		if ($os eq "darwin") {
			$status_icon->signal_connect("popup-menu",sub { $obj->show_menu(); });
		} else {
			$status_icon->signal_connect("activate",sub { $obj->show_men(); });
		}
		$status_icon->set_visible(1);
		$obj->{icon}=$status_icon;
		$obj->{icon_type}="status";
	} else {
		my $status_icon=Gtk2::AppIndicator->new("PerlShare","tray_active_0");
		
		$status_icon->set_icon_theme_path($img_dir);
		for my $i qw(0 1 2 3 4 5 6 7 8) {
			$obj->{"icn_active_$i"}="tray_active_$i";
			$obj->{"icn_collision_$i"}="tray_collision_$i";
		}
		$obj->{"icn_inactive"}="tray_inactive";
		$obj->{"icn_collision"}="tray_collision";
		
  	$status_icon->set_menu($menu);
  	$status_icon->set_active();
  		
		$obj->{icon}=$status_icon;
		$obj->{icon_type}="indicator";
	}
	
	$obj->{collision}=0;
	$obj->{activity}=0;
	
	bless $obj,$class;
	
	return $obj;
}

sub activity() {
	my $self=shift;
	
	my $img_dir=$self->{img_dir};
	my $activity=$self->{activity};
	$activity+=1;
	if ($activity>8) { $activity=0; }
	
	$self->{activity}=$activity;
	my $icon=$self->{icon};
	my $a="active";
	if ($self->{collision}) {
		$a="collision";
	}
	my $pb=$self->{"icn_$a"."_$activity"};
	if ($self->{icon_type} eq "status") {
		$icon->set_from_pixbuf($pb);
	} else {
		$icon->set_icon_name_active($pb);
	}
}

# 1 or 0
sub set_collision() {
	my $self=shift;
	$self->{collision}=shift;
}

sub begin_sync() {
	my $self=shift;
	my $space_name=shift;
	$self->{collision}=0;
}

sub end_sync() {
	my $self=shift;
	my $icon=$self->{icon};
	my $img_dir=$self->{img_dir};
	
	my $a="inactive";
	if ($self->{collision}) {
		$a="collision";
	}
	my $pb=$self->{"icn_".$a};
	
	if ($self->{icon_type} eq "status") {
		$icon->set_from_pixbuf($pb);
	} else {
		$icon->set_icon_name_active($pb);
	}
}

sub show_menu() {
  my $self = shift;
  my $menu = $self->{popup_menu};
  $menu->popup(undef,undef,undef,undef,0,0);
}

1;



