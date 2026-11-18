(* ------------------------------------------------------------- the icon

   A Sun notes that came from an installer already has an icon, and nothing
   below has anything to add: the macOS bundle carries one in
   Contents/Resources and names it in Info.plist, the .deb and the .rpm
   install one under hicolor together with a desktop entry, and the Windows
   installer embeds one in the .exe. The system reads all of those before this
   program starts.

   Built from a clone of the repository there is no package, and the window
   wears the generic executable icon. What follows is for that case only: the
   application id and the icon are set by hand, and --install-icon writes the
   desktop entry Linux needs. [packaged] below is what tells the two apart. *)

let app_id = "sun-notes"

(* True when the layout around the binary already provides an icon.

   Each test looks for the very file the system reads the icon from, rather
   than trying to work out how the binary was installed. *)
let packaged () =
  let exe = Sys.executable_name in
  let dir = Filename.dirname exe in
  (* macOS: the executable sits in "Sun notes.app"/Contents/MacOS, and the
     Dock takes the icon from Contents/Info.plist (CFBundleIconFile). *)
  (Filename.basename dir = "MacOS"
  && Sys.file_exists (Filename.concat (Filename.dirname dir) "Info.plist"))
  (* Windows: the installer leaves sun-notes.ico beside the .exe for the Start
     menu and desktop shortcuts to point at, and embeds the same image in the
     binary. Nothing stages that file in a build tree. *)
  || Sys.file_exists (Filename.concat dir (app_id ^ ".ico"))
  (* Linux: the .deb and the .rpm install the binary as
     /usr/lib/sun-notes/sun-notes, next to a desktop entry whose
     StartupWMClass is that same "sun-notes" — which is what GTK calls the
     process, so the shell matches the window to the entry with no help from
     us. Both halves are tested, because the entry on its own is also there
     for someone who has the package installed and runs a build tree too: that
     main.exe matches nothing, and does need the calls below. *)
  || Filename.basename exe = app_id
     && Sys.file_exists ("/usr/share/applications/" ^ app_id ^ ".desktop")

(* ------------------------------------------------------- the data files

   The page and the icon are files on disk, and there are two places they can
   be. A build tree stages them beside the binary, in _build/default/run/; an
   `opam install` puts the binary in <prefix>/bin and its data in
   <prefix>/share/sun-notes. See run/dune, which arranges both.

   Both are expressed relative to the executable rather than to the current
   directory, which is what [Locate_assets] is for: the program can be started
   from anywhere, and a switch that is moved or copied takes its bin/ and
   share/ along together. *)
let data_path name =
  let resolve = Webview_desktop.Locate_assets.assets_dir in
  let beside = resolve name in
  if Sys.file_exists beside then beside
  else
    let installed = resolve (Filename.concat "../share/sun-notes" name) in
    (* The build-tree path on failure, not the installed one: someone whose
       files are missing is nearly always someone who has not run `dune
       build`, and that is the path they need to see. *)
    if Sys.file_exists installed then installed else beside

(* The icon. Absent from a packaged install -- the .deb, .rpm, .dmg and
   Windows installer carry their own, converted to the format each system
   wants -- which is exactly the case where nothing below asks for it. *)
let icon_path () = data_path "logo.png"

(* --install-icon: write the desktop entry a Linux desktop needs before it
   will show the icon at all.

   Under Wayland — the default on current GNOME — there is no window icon
   property to set: the shell resolves an application's icon from an installed
   .desktop file, matched against the process by its application id. So
   setting the icon from the program is not enough there, and an unpackaged
   build has to install an entry of its own. All the work is
   owebview.desktop's; what is left here is the labels, which match the ones
   the .deb and .rpm write, and what to tell the user afterwards. *)
let install_icon () =
  if packaged () then (
    print_endline
      "Nothing to do: this Sun notes came from an installer, which carries its \
       own icon and whatever the system needs in order to find it.";
    exit 0);
  match
    Webview_desktop.Icon.install_desktop_entry ~app_id ~icon:(icon_path ())
      ~name:"Sun notes" ~comment:"A note-taking app written in OCaml"
      ~categories:[ "Office"; "Utility"; "TextEditor" ] ()
  with
  | None ->
      prerr_endline
        "--install-icon only applies on Linux: elsewhere the icon is set by \
         the application itself, which it already does.";
      exit 1
  | Some path ->
      Printf.printf "Installed %s\n" path;
      print_endline
        "Start Sun notes again — the icon should now show in the dock, the \
         taskbar or the window switcher.";
      Printf.printf "Undo with: rm %s\n" (Filename.quote path)

(* ------------------------------------------------------------- the window *)

let run_window () =
  (* Library version info (no window needed). *)
  let v = Webview.version () in
  (* Through Binding.trace like everything else: a graphical program launched
     from Explorer has no valid standard output, and writing to it would raise
     rather than be ignored. *)
  Binding.trace "using webview %s\n%!" v.Webview.version_number;

  let unpackaged = not (packaged ()) in

  (* Linux only, a no-op elsewhere, and it has to come before [create] so that
     it applies to the first window realized. This is the id the desktop entry
     carries as StartupWMClass — whether the one a package installed or the one
     --install-icon writes — so the two have to agree, and passing the same
     string to both is what arranges that. *)
  if unpackaged then Webview_desktop.Icon.set_app_id app_id;

  let w = Webview.create ~debug:true () in
  Webview.set_title w "Sun notes";
  (* Two columns side by side need more room than the 480x320 the example
     started with, and the output pane is now meant to hold a whole file. *)
  Webview.set_size w ~width:900 ~height:600 Webview.Hint_none;

  (* Native handles (opaque pointers, for platform-specific FFI such as a file
     dialog). 0n means unavailable. *)
  Binding.trace "native window handle = %nx\n%!" (Webview.get_window w);
  ignore (Webview.get_native_handle w Webview.Browser_controller);

  (* Every call the page can make into the native side lives in binding.ml,
     where each one is an Lwt computation rather than work done on the UI
     thread. They are registered here, before the page is loaded, so that
     nothing it does at startup finds a missing function. *)
  Binding.install w;

  (* Load the page from on-disk files (web/) instead of an inline HTML string.
     The CSS and JS referenced with relative paths in index.html are resolved
     relative to that file, so the whole page follows from this one path. *)
  let index = Filename.concat (data_path "web") "index.html" in
  Webview.navigate w ("file://" ^ index);

  (* The icon, for the Dock on macOS, the taskbar on Windows and X11.
     Dispatched rather than called outright: on macOS the process only becomes
     a Dock-visible application once [run] has started, and an icon set before
     that is ignored. Under Wayland this has no effect at all — the entry
     --install-icon writes is what works there.

     Failure to load the image is traced, not raised: this runs on the UI
     thread, where an escaping exception would take the window down over a
     cosmetic detail. *)
  if unpackaged then
    Webview.dispatch w (fun w ->
        let icon = icon_path () in
        if Sys.file_exists icon then
          try Webview_desktop.Icon.set_app_icon w icon
          with Failure msg -> Binding.trace "set_app_icon: %s\n%!" msg
        else Binding.trace "no logo.png beside the binary — run `dune build`\n%!");

  (* The two event loops get a thread each, and the assignment is not
     arbitrary: Cocoa requires the UI loop to own the process's main thread, so
     [Webview.run] keeps it and Lwt moves to a spawned thread. Started before
     [Webview.run] so the Lwt loop is up by the time the page can call a
     binding — [Lwt_preemptive.run_in_main] has nowhere to hand work otherwise. *)
  let _ : Thread.t =
    Thread.create (fun () -> Lwt_main.run (Binding.serve ())) ()
  in

  (* The native menu bar.

     [Menu.set] has to run on the UI thread, and on macOS only once the
     application is active — which it becomes when [Webview.run] starts. Hence
     [Webview.dispatch]: the callback is queued now and runs on the UI thread
     once the loop is up.

     Every item does the same thing: call one function in the page, which
     decides what the action means (see run/web/app.ml). Keeping the decision
     there rather than here means the menu needs to know nothing about tabs,
     selections or the clipboard.

     The first menu is the application menu by macOS convention — the system
     draws it with the application's own name whatever title it is given, and
     expects Quit to live there. *)
  Webview.dispatch w (fun w ->
      let open Webview_desktop.Menu in
      (* Traced, because a menu item that does nothing gives no other sign of
         whether its callback ran at all — and on Windows an accelerator has
         two routes to travel before it gets here. *)
      let page action () =
        Binding.trace "menu: %s\n%!" action;
        (* Item callbacks run on the UI thread, so eval needs no dispatch of
           its own. The action name is quoted rather than interpolated raw: it
           is a literal here, but the day one contains an apostrophe is not the
           day to discover that. *)
        Webview.eval w
          (Printf.sprintf "window.sunNotesMenu(%s)" (Utils.quote action))
      in
      set w
        [
          ( "Sun notes",
            [
              item "Quit" ~key:'q' ~modifiers:[ Cmd ] (fun () ->
                  Binding.trace "menu: quit\n%!";
                  Webview.terminate w);
            ] );
          ( "File",
            [
              item "Save" ~key:'s' ~modifiers:[ Cmd ] (page "save");
              separator;
              item "Open Folder\xe2\x80\xa6" ~key:'o' ~modifiers:[ Cmd ]
                (page "open-folder");
            ] );
          ( "Edit",
            [
              item "Cut" ~key:'x' ~modifiers:[ Cmd ] (page "cut");
              item "Copy" ~key:'c' ~modifiers:[ Cmd ] (page "copy");
              item "Paste" ~key:'v' ~modifiers:[ Cmd ] (page "paste");
            ] );
        ]);

  Webview.run w;
  Webview.destroy w

(* No argument is how the application is always started by a dock, a shortcut
   or a desktop entry — none of them passes one, which is also why the paths
   that print below can count on having a console to print to. *)
let () =
  match List.tl (Array.to_list Sys.argv) with
  | [] -> run_window ()
  | [ "--install-icon" ] -> (
      try install_icon ()
      with Failure msg ->
        prerr_endline msg;
        exit 1)
  | _ ->
      prerr_endline "usage: sun-notes [--install-icon]";
      exit 2
