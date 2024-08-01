using Toybox.Application as App;
using Toybox.Background;
using Toybox.System as Sys;
using Toybox.Communications as Comm;
using Toybox.WatchUi as Ui;
using Toybox.Time;
using Toybox.Time.Gregorian;


class WikiNLApp extends App.AppBase {
    var inBackground=false;

    function initialize() {
      AppBase.initialize();
    }

    function onStart(state) {
    }
    
    function getInitialView() {
      return [ new WikiNLView(), new WikiNLBehaviourDelegate() ];
    }
  
}