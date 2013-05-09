#!/usr/bin/perl
use strict;
use threads;
use Thread::Queue;
use Glib qw(TRUE FALSE);
#use Gtk2 qw/-init -threads-init 1.050/;
use Gtk2 qw/-init/;
use Tray;
use Shares;
use Unison;
use PerlShareCommon::Dirs;
use PerlShareCommon::Str;
use PerlShareCommon::Log;

use sigtrap qw(die normal-signals);

die "Glib::Object thread safetly failed"
	unless Glib::Object->set_threadsafe (TRUE);
	
log_file(log_dir()."/perlshare.log");

######################################################################################
# Main 
######################################################################################

my $os = $^O;
log_info("OS = $os");

if ($os eq "darwin") {
  my $app=new Gtk2::OSXApplication();
  my $menubar=Gtk2::MenuBar->new();
  my $menu=Gtk2::Menu->new();
  my $item=Gtk2::MenuItem->new_with_label("Info");
  $item->set_submenu($menu);
  my $about=Gtk2::MenuItem->new_with_label("About");
  $menu->append($about);
  $menubar->append($item);
  $about->show();
  $item->show();
  $menu->show();
  $menubar->show();
  $app->set_menu_bar($menubar);
  $app->ready();
}

# Global menu
my $shares = new Shares();
my $menu = Gtk2::Menu->new();
my $status_icon;

if ($os=~/^MSWin/ || $os eq "darwin") {
  $status_icon = new Tray(images_dir(), $menu, "statusicon");
} else {
  $status_icon = new Tray(images_dir(), $menu, "appindicator");
}

my $data_queue = new Thread::Queue();

log_debug("Starting timeout sub");
Glib::Timeout->add(100, sub {
    my $data = $data_queue->dequeue_nb();
    while (defined($data) && $data ne "quit") {
      my ($share, $state, $code) = split(/,/,$data);

      #log_info("share = $share, state = $state, code = $code");
      if ($code > 0) {
        $shares->associate($share, "code", $code);
      } elsif ($state eq "disconnected") {
        $shares->associate($share, "code", -1);
        $code = -1;
      } elsif ($state eq "connected") {
        $shares->associate($share, "code", 0);
        $code = 0;
      }
      $status_icon->set_collision($code > 0);
  
      if ($state eq "starting") {
        $status_icon->begin_sync();
      } elsif ($state eq "running") {
        $status_icon->activity();
      } elsif ($state eq "done" || $state eq "disconnected" || $state eq "connected") {
        $shares->associate($share, "code", $code);
        
        #if ($state eq "done") {
          my @S = $shares->get_shares();
          
          my $red = 0;
          my $gray = 1;
          foreach my $sharename (@S) {
            my $code = $shares->get_assoc($sharename, "code");
            #log_info("$sharename - code = $code");
            if ($code > 0) { $red = 1;$gray = 0; }
            elsif ($code == 0) { $gray = 0; }
          }
          $status_icon->set_collision($red);
          $status_icon->set_gray($gray);
          $status_icon->end_sync();
        #}
        
        my $image_menu_item = $shares->get_assoc($share,"menu-item");
        my $img = ($code > 0) ? image_nok() :
                    (($code < 0) ? image_disconnected() : image_ok());
        $image_menu_item->set_image($img);
      }
      
      $data = $data_queue->dequeue_nb();
    }
    if ($data eq "quit") {
      return 0;
    } else {
      return 1;
    }
});

create_menu($shares, $status_icon, $data_queue);
$shares->synchronizer(sub { report_cb(@_, $data_queue); });

Gtk2::main(undef);

######################################################################################
# Supporting functions
######################################################################################
  
sub create_menu($$$) {
  my $shares = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $menu = Gtk2::Menu->new();
  
  my $mnu_create_share = Gtk2::MenuItem->new("_Create share");
  my $mnu_quit = Gtk2::MenuItem->new("_Quit");
  
  $menu->append($mnu_create_share);
  $menu->append(Gtk2::SeparatorMenuItem->new());
  
  my @S = $shares->get_shares();
  foreach my $share (@S) {
    my $mnu = Gtk2::ImageMenuItem->new($share);
    my $img = image_ok();
    $mnu->set_image($img);
    my $submenu = Gtk2::Menu->new();
    my $mnu_drop = Gtk2::MenuItem->new("_Drop share");
    my $mnu_web = Gtk2::MenuItem->new("_Website");
    #my $mnu_col = Gtk2::MenuItem->new("_Resolve collision");
    my $mnu_map = Gtk2::MenuItem->new("_Open folder");
    
    $submenu->append($mnu_map);
    #$submenu->append($mnu_col);
    $submenu->append($mnu_web);
    $submenu->append(Gtk2::SeparatorMenuItem->new());
    $submenu->append($mnu_drop);
    $mnu_map->signal_connect("activate", sub { open_share($shares,$share); });
    #$mnu_col->signal_connect("activate", sub { share_collision($shares,$share); });
    $mnu_web->signal_connect("activate", sub { share_web($shares,$share); });
    $mnu_drop->signal_connect("activate", sub { share_drop($shares,$share); });
    
    $mnu->set_submenu($submenu);
    $menu->append($mnu);
    
    $shares->associate($share,"menu-item",$mnu);
  }
  
  $menu->append(Gtk2::SeparatorMenuItem->new());
  $menu->append($mnu_quit);
  
  $mnu_quit->signal_connect("activate", sub { quit($shares); });
  $mnu_create_share->signal_connect("activate", sub { create_share($shares, $status_icon, $data_queue); });
  
  $menu->show_all();
  
  $status_icon->set_menu($menu);
  
  return $menu;
}

sub image_ok() {
  return get_scaled_image("tray_inactive.png");
#  return Gtk2::Image->new_from_file
}

sub image_nok() {
  return get_scaled_image("tray_collision.png");
  #return Gtk2::Image->new_from_file(images_dir()."/tray_collision.png");
}

sub image_disconnected() {
  return get_scaled_image("tray_gray.png");
  #return Gtk2::Image->new_from_file(images_dir()."/tray_gray.png");
}

sub get_scaled_image($) {
  my $name = shift;
  my ($w,$h) = Gtk2::IconSize->lookup('menu');
  my $pb = Gtk2::Gdk::Pixbuf->new_from_file_at_size(images_dir()."/$name", $w, $h);
  return Gtk2::Image->new_from_pixbuf($pb);
}

sub quit($) {
  my $shares = shift;
  Gtk2::main_quit();
}

######################################################################
# Create share
######################################################################

sub create_share($$) {
  my $shares = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $dialog = Gtk2::Dialog->new();
  $dialog->set_title("PerlShare - Create Share");
  
  my $lbl_share = Gtk2::Label->new("The Name of the Share:");
  my $lbl_server = Gtk2::Label->new("PerlShare Server Hostname:");
  my $lbl_email = Gtk2::Label->new("Your registered email adress:");
  my $lbl_pass = Gtk2::Label->new("Your registered password:");
  my $chk_local = Gtk2::CheckButton->new("Create share under different local name:");
  $lbl_share->set_alignment(0.0, 0.5);
  $lbl_server->set_alignment(0.0, 0.5);
  $lbl_email->set_alignment(0.0, 0.5);
  $lbl_pass->set_alignment(0.0, 0.5);
  
  my $entry_share = Gtk2::Entry->new();
  my $entry_server = Gtk2::Entry->new();
  my $entry_email = Gtk2::Entry->new();
  my $entry_pass = Gtk2::Entry->new();
  my $entry_local = Gtk2::Entry->new();
  $entry_pass->set_visibility(0);
  $entry_local->set_editable(0);
  $entry_local->set_sensitive(0);
  $chk_local->signal_connect("toggled", sub { 
    $entry_local->set_editable($chk_local->get_active());
    $entry_local->set_sensitive($chk_local->get_active());
  });
  
  my $table = Gtk2::Table->new(4,2);
  $table->attach_defaults($lbl_share, 0, 1, 0, 1);
  $table->attach_defaults($chk_local, 0, 1, 1, 2);
  $table->attach_defaults($lbl_server, 0, 1, 2, 3);
  $table->attach_defaults($lbl_email, 0, 1, 3, 4);
  $table->attach_defaults($lbl_pass, 0, 1, 4, 5);
  $table->attach_defaults($entry_share, 1, 2, 0, 1);
  $table->attach_defaults($entry_local, 1, 2, 1, 2);
  $table->attach_defaults($entry_server, 1, 2, 2, 3);
  $table->attach_defaults($entry_email, 1, 2, 3, 4);
  $table->attach_defaults($entry_pass, 1, 2, 4, 5);
  
  my $vbox = $dialog->vbox;
  my $frame = Gtk2::Frame->new();
  $frame->add($table);
  $vbox->pack_start($frame,0,0,4);
  
  $vbox->show_all();
  
  $dialog->add_button("_Cancel", 0);
  $dialog->add_button("_Create", 1);
  my $response = 2;
  
  while ($response == 2) {
    $response = $dialog->run();
    if ($response == 0) {
      # do nothing
    } else {
      my $sharename = trim($entry_share->get_text());
      my $host = trim($entry_server->get_text());
      my $email = trim($entry_email->get_text());
      my $pass = trim($entry_pass->get_text());
      my $local = "";
      $local = trim($entry_local->get_text()), if ($chk_local->get_active());
      
      my $nok = undef;
      if ($sharename=~/\s+/ || $local=~/\s+/) {
        $nok = "A name of a share may not contain spaces or tabs";
      } elsif ($sharename eq "") {
        $nok = "A share name must be given";
      } elsif ($host eq "") {
        $nok = "A hostname is mandatory";
      } elsif ($email eq "") {
        $nok = "Your registered email addres (or account) must be given";
      } elsif ($pass eq "") {
        $nok = "A password is mandatory (it won't be stored locally)";
      }
      
      if (defined($nok)) { # Error
         show_message_dialog($dialog, "PerlShare - Create Share", 'error', "Creating share", $nok);
         $response = 2;
      } else {
        my $result = $shares->create_share($sharename, $host, $email, $pass, $local);
        if ($result == 0) { # Error
          show_message_dialog($dialog, "PerlShare - Create Share", 'error', "Creating share", $shares->get_message());
          $response = 2;
        } else { # recreate menu
          my $menu = create_menu($shares, $status_icon, $data_queue);
          show_message_dialog($dialog, "PerlShare - Create Share", 'info', "Creating Share", "Share $sharename has sucessfully been created");
          sync_now($shares, $sharename, $status_icon, $data_queue);
        }
      }
    }
  }
  
  $dialog->destroy();
}

sub share_collision($) {
  my $shares = shift;
  my $share = shift;
  my $thr=threads->create(sub {
    my $shr = shift;
    my $unison = new Unison();
    $unison->run_gui($shr);
  }, $share);
  $thr->detach();
}

sub open_share($$) {
  my $shares = shift;
  my $share = shift;
  
  my $dir = perlshare_dir($share);
  log_info("opening $dir");
  
  my $os = $^O;
  if ($os =~ /^MSWin/) {
    $dir=~s%/%\\%g;
    system("start explorer \"$dir\"");
  } elsif ($os eq "darwin") {
    system("open '$dir'");
  } else {
    system("xdg-open '$dir'");
  }
}

sub share_web($$) {
  my $shares = shift;
  my $share = shift;
  my ($host, $email) = $shares->get_share_info($share);
  
  my $url = "http://$host?login=$email";
  my $os = $^O;
  if ($os=~/MSWin/) {
    system("start $url");
  } else {
    Gtk2::show_uri(Gtk2::Gdk::Screen->get_default(),$url);
  }
}

sub share_drop($$) {
  my $shares = shift;
  my $share = shift;
  
  my $response = ask_yn_message(
    undef, 
    "PerlShare - Drop Share", 
    'question', 
    "Dropping share '$share'",
    "Contents will remain on the server and local, but synchronization ".
    "will stop. If you want to remove this share all together, please do ".
    "this at the website.\n\n".
    "Are you sure you want to remove this share from synchronizing?"
    );
  log_info("result = $response");
  
}

sub sync_now($$) {
  my $shares = shift;
  my $share = shift;
  my $status_icon = shift;
  my $data_queue = shift;
  
  my $thr=threads->create(sub {
    my $shr = shift;
    my $unison = new Unison();
    $unison->run($shr, sub { report_cb(@_, $data_queue); }, 1);
  }, $share);
  $thr->detach();
}

sub report_cb($$$$) {
  my $sharename = shift;
  my $state = shift;
  my $code = shift;
  my $data_queue = shift;
  
  $data_queue->enqueue("$sharename,$state,$code");
}


# $icon can be one of the following:	
#         a) 'info'
#					b) 'warning'
#					c) 'error'
#					d) 'question'
sub show_message_dialog($$$$;$) {
  return message_dialog('ok', @_);
}

sub ask_yn_message($$$$;$) {
  return message_dialog('yes-no', @_);
}

sub message_dialog($$$$$;$) {
  my ($buttons, $parent, $title, $icon, $text, $subtext) = @_;
  
  my $t1 = $title;
  if (defined($subtext)) { $t1 = $text; }
  my $t2 = $text;
  if (defined($subtext)) { $t2 = $subtext; }
  
  my $dialog = Gtk2::MessageDialog->new_with_markup ($parent,
  					[qw/modal destroy-with-parent/],
  					$icon,
  					$buttons,
  					sprintf "<b>$t1</b>");
  $dialog->set_title($title);
  if ($t2) { $dialog->format_secondary_text($t2); }
  
  my $response = $dialog->run;
 	$dialog->destroy;
 	
 	return $response;
}




