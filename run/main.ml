let () =
  (* Library version info (no window needed). *)
  let v = Webview.version () in
  (* Through Binding.trace like everything else: a graphical program launched
     from Explorer has no valid standard output, and writing to it would raise
     rather than be ignored. *)
  Binding.trace "using webview %s\n%!" v.Webview.version_number;

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
     relative to that file. We locate the web/ directory from the executable
     location, so it works both installed and from the build tree. *)
  let index =
    Filename.concat (Webview_desktop.Locate_assets.web_dir ()) "index.html"
  in
  Webview.navigate w ("file://" ^ index);

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
      let page action () =
        (* Item callbacks run on the UI thread, so eval needs no dispatch of
           its own. The action name is quoted rather than interpolated raw: it
           is a literal here, but the day one contains an apostrophe is not the
           day to discover that. *)
        Webview.eval w
          (Printf.sprintf "window.sunNotesMenu(%s)" (Utils.js_quote action))
      in
      set w
        [
          ( "Sun notes",
            [ item "Quit" ~key:'q' ~modifiers:[ Cmd ] (fun () -> Webview.terminate w) ] );
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
