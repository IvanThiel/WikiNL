using Toybox.WatchUi as Ui;
using Toybox.Background;

class WikiNLBehaviourDelegate extends Ui.BehaviorDelegate {
    function initialize() {
      BehaviorDelegate.initialize();
    }

    function onTap(evt) {
      //debug("onTap type = "+_touch_type);

      //var xx = evt.getCoordinates()[0];
      var yy = evt.getCoordinates()[1];
      if (yy<mH/2) {
        GlobalTouched = 1;
        Ui.requestUpdate();
        return true;
      }

     
      return false;    
    }

}