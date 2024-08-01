using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Communications as Comm;
using Toybox.System as Sys;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.Application as App;
using Toybox.Position;
using Toybox.Background;
using Toybox.Application.Storage;


const RAY_EARTH   = 6378137d;   
var GlobalTouched = -1;
var mW;
var mH;
var mSH;
var mSW;

var _debug       = false;
var _cslastpos   = null;
var _cslat       = null;
var _cslong      = null;
var _csstartpos  = null;
var _csInNL      = true;

/*
  Wikipedia
   
  -- EN

  Tap on the top of the field to get an updated list of sight in a radius of 1500m.
  You need a connected phone with Internet.


  -- NL

  Als je geen idee hebt waar je eigenlijk aan het fietsen bent kun je dit dataveld gebruiken om wat info te krijgen:
  - de gemeente, woonplaats wijk en buurt (via https://api.pdok.nl/)
  - de bezienswaardigheden volgens wikipedia in een straal van 1500m (via https://nl.wikipedia.org/)

  Het dataveld haalt elke 5 minuten de gegevens op als het veld zichtbaar is. Je kunt ook tikken op het bovenste gedeelte van het veld om meteen de gegevens op te halen.
  Maak een extra groot 1 veld scherm aan op je Garmin, en navigeer naar het scherm als je wilt weten waar je eigenlijk aan het fietsen bent. Als je normaal breed veld gebruikt kun je alleen de gemeente info zien.

  Je hebt een telefoon verbinding met Internet nodig. 
*/

class WikiNLView extends Ui.DataField {
    hidden const OFFSETY       = - 6;
    hidden const  NAV_INFO_BOX = 300;
    hidden const _180_PI       = 180d/Math.PI;
    hidden const _PI_180       = Math.PI/180d; 

    hidden var   YMARGING  = 25;
    hidden var   XMARGING  = 6;
   
    hidden var mLabel1    = "";
    hidden var mLabel2    = "";
    hidden var mLabel3    = "";
    hidden var mLabel4    = "";
    hidden var mLabel5    = "";
    hidden var mGpsSignal = 0;

    hidden var mSF1  = Gfx.FONT_GLANCE;
    hidden var mSF1N = Gfx.FONT_GLANCE_NUMBER;
    hidden var mSF4  = Gfx.FONT_SMALL;
    hidden var mSF2  = Gfx.FONT_TINY;
    hidden var mSF3  = Gfx.FONT_XTINY;

    hidden var mBearing;
    hidden var mTrack;
    hidden var mHome;

    hidden var mLoading = false;

    hidden var mLoadingCount = 0;
    hidden var mLastMinute = 0;

    hidden var mProvincie  = "";
    hidden var mGemeente   = "";
    hidden var mWoonplaats = "";
    hidden var mBuurt      = "";
    hidden var mWijk       = "";
    hidden var mLoadError  = "";
    hidden var mConnectie = false;
    hidden var mWiki = new[25];
    hidden var mCurrentLocation = null;
    hidden var mWikiResults = 5;
    hidden var mLastWikiRange = 1500;
    hidden var mLastWiki  = null;
    hidden var mLastWikiLat = null;
    hidden var mLastWikiLon = null;
    
    /******************************************************************
     * INIT 
     ******************************************************************/  
    function initialize() {
      try {
        DataField.initialize();  
      } catch (ex) {
        debug ("init error: "+ex.getErrorMessage());
      }         
    }

    /******************************************************************
     * HELPERS 
     ******************************************************************/  
    function debug (s) {
      try {
        if (s==null) {
          return;
        }
        if (_debug) {
          System.println("WikiNLView: "+s);
        } 
        if ((s instanceof String) && (s.find(" error:")!=null)) {
          if (!_debug) {
            System.println("=== ERROR =================================================================");
            var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            var v = now.hour.format("%02d")+":"+now.min.format("%02d")+":"+now.sec.format("%02d");
            System.println(v);
            System.println(""+s);
            System.println("WikiNLView: "+s);
            System.println("===========================================================================");
          }
        }
      } catch (ex) {
        System.println("debug error:"+ex.getErrorMessage());
      }
    }

    function trim (s) {
      var l = s.length();
      var n = l;
      var m = 0;
      var stop;

      stop = false;
      for (var i=0; i<l; i+=1) {
        if (!stop) {
          if (s.substring(i, i+1).equals(" ")) {
            m = i+1;
          } else {
            stop = true;
          }
        }
      }

      stop = false;
      for (var i=l-1; i>0; i-=1) {
        if (!stop) {
          if (s.substring(i, i+1).equals(" ")) {
            n = i;
          } else {
            stop = true;
          }
        }
      }  

      if (n>m) {
        return s.substring(m, n);  
      } else {
        return "";
      }
    }

    function stringReplace(str, oldString, newString) {
      var result = str;

      while (true) {
        var index = result.find(oldString);

        if (index != null) {
          var index2 = index+oldString.length();
          result = result.substring(0, index) + newString + result.substring(index2, result.length());
        }
        else {
          return result;
        }
      }

      return null;
    }

    /******************************************************************
     * COMMUNICATION 
     ******************************************************************/  
    function killComm () {
      debug("KillComm");
      try {
        Communications.cancelAllRequests();
      } finally {
        mLoadingCount = 0;
        if (mLoading) {
          mLoadError = "LOADING CANCELLED";
        }
        mLoading = false;
      }
    }

    /*** WIKI ***/
    function  bubbleSort(a) {
      var n = a.size();
      
      var swapped = false;
      do {
        swapped = false;
        for (var i=1; i<n; i+=1) {
           if (a[i]!=null) {
             if (a[i-1]["d"]>a[i]["d"]) {
                var b = a[i-1];
                a[i-1] = a[i];
                a[i] = b;
                swapped = true;
             }
           }
          
        }
     } while (swapped);
    }
    
    function calcDistance (lat, lon) {
      var distance = 0;
      var dir = 0;

      if (mCurrentLocation!=null) {
        var latitude_point_start  = mCurrentLocation.toRadians()[0].toDouble();
        var longitude_point_start = mCurrentLocation.toRadians()[1].toDouble();

        if ((lat != null) && (latitude_point_start !=null)) {
          distance = Math.acos(Math.sin(latitude_point_start)*Math.sin(lat) + 
                     Math.cos(latitude_point_start)*Math.cos(lat)*Math.cos(longitude_point_start-lon));

          if( distance > 0) {
            dir = Math.acos((Math.sin(lat)-Math.sin(latitude_point_start)*Math.cos(distance))/(Math.sin(distance)*Math.cos(latitude_point_start)));
            if( Math.sin(lon-longitude_point_start) <= 0 ) {
              dir = 2*Math.PI-dir;
            }
            distance = RAY_EARTH * distance;
          }
        }
      }
      return [distance, dir];
    }

    function resetWiki() {
      // init
      var m = mWiki.size();
      for (var i=0; i<m; i += 1) {
        mWiki[i] = null;
      }
    }

    function recomputeWiki() {
      try {

        if (mWiki==null) {
          return;
        }

        var n = mWiki.size();
        if ((n==0) || (mWiki[0]==null) ) {
          return;
        }

        for (var i=0; i<n; i++) {
          if (mWiki[i]!=null) {
            var dd = calcDistance (mWiki[i]["lat"], mWiki[i]["long"]);
            mWiki[i]["d"] = dd[0];
            mWiki[i]["a"] = dd[1]; 
          }  
         } 
         bubbleSort(mWiki); 
      } catch (ex) {
        debug("recompute wiki: "+ex.getErrorMessage());
      }
    }
     
    function parseWiki(data) {
      try {
        var j = 0;
 
        // init
        resetWiki();
        var m = mWiki.size();
      
        if ( (data!=null) && (data["query"]!=null)  ) {
          var n = data["query"]["pages"].keys().size();

          for(var index = 0; index < n; index++) {
            var key = data["query"]["pages"].keys()[index];
            var value = data["query"]["pages"][key];
            var latitude_point_arrive;
            var longitude_point_arrive ;

            if (
                 ( value["coordinates"]    !=null ) &&
                 ( value["coordinates"][0] != null ) &&
                 ( value["coordinates"][0]["lat"]!=null) &&
                 ( value["coordinates"][0]["lon"]!=null) 
               ) {
               
              latitude_point_arrive  = value["coordinates"][0]["lat"].toDouble()*Math.PI/180;
              longitude_point_arrive = value["coordinates"][0]["lon"].toDouble()*Math.PI/180;

              if (j<m) {  
                var des="";
                if ( (value ["terms"]!=null) && (value ["terms"]["description"]!=null) ) {
                         des = value ["terms"]["description"][0] ;
                }

                if (
                      (des.find("straat in")==null) &&
                      (des.find("buurt in")==null) &&
                      (des.find("wijk in")==null) &&
                      ((mBuurt.length()==0) || (des.find(mBuurt)==null)) &&
                      (des.find("sneltramhalte")==null) &&
                      (des.find("weg in")==null) 
                   ) {
                  mWiki[j] = { 
                      "t"   => value["title"], 
                      "des" => des,
                      "d"   => 0,
                      "a"   => 0,
                      "lat" => latitude_point_arrive,
                      "long" => longitude_point_arrive
                    };
                  j += 1;
                }
              }
            }  
          } // for 
        } 
      
        debug("getWiki results: "+j);
        mWikiResults = j;


        data = null;
      } catch (ex) {
        data = null;
        debug("parseWiki error: "+ex.getErrorMessage());
      }    
    }
  
    function setWikiHint() {
      if ((!mLoading) && (mWiki!=null)) {
        if (mWiki[0]==null) {
          mWiki[0] = { "t" => "No information",  "a"=>0, "d"=>0, "des" => "Tap here to refresh.", "lat" => 0, "long" => 0 };
        }
      }
    }


    function receiveWiki(responseCode, data) {
      debug("getWiki "+responseCode);  
      //debug("getWiki "+data);  
      var parse = true;
      mLoading = false;
      mLoadingCount = 0;
      //debug("Wiki: "+data);     
      if (responseCode!=200) {
        // invalid response, wipe the data
        parse = false;  
        mLoadError = "wiki: "+responseCode;    
      } else {
 
      }
   
      if (parse) {
        parseWiki(data);
      }
      data = null;
    }

    function getWiki(num) {
      debug("getWiki");  

      if (!mConnectie) {
        debug("getWiki: skipped geen connectie");
        return;
      }   

      num          = 10;
      mLoading      = true;
      mLoadingCount = 1;
      mLoadError    = "";

      var range = mLastWikiRange;

      try {
          var lat     = _cslat;
          var long    = _cslong;
          var lang    = "nl";

          if (!_csInNL) {
            lang = "en";
          }

          // https://en.wikipedia.org/w/api.php?action=help&modules=query+geosearch
          // https://www.mediawiki.org/wiki/Extension:GeoData#list.3Dgeosearch
    
          Communications.makeWebRequest(
              "https://"+lang+".wikipedia.org/w/api.php"
              ,
              {
                "action"    => "query"
               ,"ggscoord"  => lat+"|"+long
               ,"prop"      => "coordinates|pageterms"
               ,"colimit"   => num
               ,"wbptterms" => "description"
               ,"generator" => "geosearch"
               ,"ggsradius" => range
               ,"ggslimit"  => "20"
               ,"format"    => "json"
              },
              {
                  "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
              },
              method(:receiveWiki)
            );
            mLastWiki= Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            mLastWikiLat = _cslat.toDouble()*Math.PI/180;
            mLastWikiLon = _cslong.toDouble()*Math.PI/180;
      } catch (ex) {
           mLoading = false;
           mLoadingCount = 0;
           debug("getWiki error: "+ex.getErrorMessage());        
      }

    }

    /*** WOONPLAATS ***/
    function quickTestNL() {
      var lat     = _cslat;
      var long    = _cslong;

      if ((lat==null) || (long==null)) {
        return false;
      }

      if (
           (lat.toFloat()  >= 50) && 
           (lat.toFloat()  <= 54) && 
           (long.toFloat() >= 3)  &&  
           (long.toFloat() <= 8)
          ) {
        return true;
      
      } else {
        _csInNL = false;
        return false;
      }
    }

    function clearAddress() {
      mGemeente = "";
      mWoonplaats = "";
      mBuurt = "";
      mWijk = "";
      mProvincie = "";
    }

    function receiveWoonplaats(responseCode, data) {
      try {
        debug("receiveWoonplaats "+responseCode);  
        mLoading = false;
        mLoadingCount = 0;
       //  debug("->  Data received with code "+responseCode.toString());  
        //debug("->  "+data); 
      
        if (responseCode==200) {  
          if (
               (data!=null) &&
               (data["response"]!=null) &&
               (data["response"]["docs"]!=null)
            )
          {
            var n = data["response"]["docs"].size();

            if (n==0) {
              _csInNL = false;
            }

            for (var i=0; i<n; i+=1) {
              var type = data["response"]["docs"][i]["type"];
              if (type.equals("wijk")) {  
                mWijk = data["response"]["docs"][i]["weergavenaam"];
              }

              if (type.equals("buurt")) {  
                mBuurt = data["response"]["docs"][i]["weergavenaam"];
              }              

              if (type.equals("gemeente")) {  
                mGemeente = data["response"]["docs"][i]["weergavenaam"];
              }  

              if (type.equals("woonplaats")) {
                mWoonplaats = data["response"]["docs"][i]["weergavenaam"];
              }
            } // for
          }  

          data = null;

            // Naam woonplaats en gemeente zijn gelijk.
            // bv "Utrecht, Utrecht, Utrecht"
            var s=mWoonplaats;
            var i;

            if (s.length()==0) {
              s = mGemeente;
            }

            i = s.find(",");
            if (i!=null) {
              // woonplaats
              mWoonplaats = s.substring(0, i);
              s = s.substring(i+1, 999);
              i = s.find(", ");
              if (i != null) {
                // gemeente
                mGemeente = s.substring(1, i);
                s = s.substring(i+1, 999);
                if (i != null) {
                  // Provincie
                  mProvincie = s.substring(1, 999);
                }
              }
            }

            // alles na ',' weghalen uit buurt
            /*
            i = mBuurt.find(",");
            if (i != null) {
              mBuurt = mBuurt.substring(0, i);
            }
            */

            // Haal wijknummer uit wijk  
            for (i=0; i<21; i+=1) {  
              s = i.format("%02d");
              //debug(">"+s+"<"); 
              mWijk = stringReplace(mWijk, "Wijk "+s, ""); 
            }  
  
            // haal woonplaats en gemeente uit buurt en wijk
            mBuurt  = " "+mBuurt+" ";
            mBuurt  = stringReplace(mBuurt, " "+mWoonplaats+" ", " ");
            mBuurt  = " "+mBuurt+" ";
            mBuurt  = stringReplace(mBuurt, " "+mGemeente+" "  , " ");
            mBuurt  = " "+mBuurt+" ";
            mBuurt  = stringReplace(mBuurt  , mWoonplaats+"-", " ");
            mBuurt  = stringReplace(mBuurt  , "  ", " ");
            mBuurt  = stringReplace(mBuurt  , "en omgeving", "");
            mBuurt  = stringReplace(mBuurt  , "Oud-Zuilen", "Oud Zuilen");

            mWijk = " "+mWijk+" ";
            mWijk  = stringReplace(mWijk  , " "+mWoonplaats+" ", " ");
            mWijk = " "+mWijk+" ";
            mWijk  = stringReplace(mWijk  , " "+mGemeente+" ", " "); 
            mWijk = " "+mWijk+" ";
            mWijk  = stringReplace(mWijk  , mWoonplaats+"-", " ");
            mWijk  = stringReplace(mWijk  , "  ", " ");
            mWijk  = stringReplace(mWijk  , "en omgeving", "");
            mWijk  = stringReplace(mWijk  , "Oud-Zuilen", "Oud Zuilen");

            mWijk  = trim(mWijk);
            mBuurt = trim(mBuurt);

            // Afkorten provincie
            mProvincie = stringReplace(mProvincie, "Utrecht", "UT");
            mProvincie = stringReplace(mProvincie, "Zuid-Holland", "ZH");
            mProvincie = stringReplace(mProvincie, "Noord-Holland", "NH");
            mProvincie = stringReplace(mProvincie, "Gelderland", "GE");
            mProvincie = stringReplace(mProvincie, "Friesland", "FR");
            mProvincie = stringReplace(mProvincie, "Groningen", "GR");
            mProvincie = stringReplace(mProvincie, "Noord-Brabant", "NB");
            mProvincie = stringReplace(mProvincie, "Flevoland", "FL");
            mProvincie = stringReplace(mProvincie, "Overijssel", "OV");
            mProvincie = stringReplace(mProvincie, "Zeeland", "ZE");
            mProvincie = stringReplace(mProvincie, "Drenthe", "DR");

            if (mWijk.equals(mBuurt)) {
                mBuurt = "";
            }

        } else {
          if (responseCode==400) {
            _csInNL = false;
          } else {
             mLoadError = "woonplaats : "+responseCode;   
          }
        }

        if (!_csInNL) {
          clearAddress();
        }
        data = null;
      } catch (ex) {
         data = null;
         mLoading = false;
         mLoadingCount = 0;
         debug("receiveWoonplaats error:"+ex.getErrorMessage());
      }
    }

    function getWoonplaats() { 
      debug("getWoonplaats");   

      if (!mConnectie) {
        debug("getWoonplaats: Geen connectie");
        return;
      }     

      if (!_csInNL) {
        debug("getWoonplaats: niet in Nederland");  
        return;   
      } 

      var lat     = _cslat;
      var long    = _cslong;

      if ((lat==null) || (long==null)) {
        return;
      }

      
      
      mLoading = true;
      mLoadingCount = 1;
      mLoadError = "";
      try {


        debug(lat+" "+long);

      /*
       https://api.pdok.nl/bzk/locatieserver/search/v3_1/ui/#/
       https://api.pdok.nl/bzk/locatieserver/search/v3_1/reverse?lat=52.119669&lon=4.985578&type=%2A&distance=1&fl=id%20type%20weergavenaam%20score%20afstand&start=0&rows=25&wt=json
      */    
       
       if (_csInNL) {
         Comm.makeWebRequest(
              "https://api.pdok.nl/bzk/locatieserver/search/v3_1/reverse",
              {
                   "lat" => lat
                  ,"lon" => long
                  //,"type" => "woonplaats"
                  ,"distance" => "0"
                  ,"type" => "*"
                  ,"wt" => "json"
                  //,"type" => "wijk"
                  //,"fl" => "type weergavenaam"
                  ,"fl" => "type weergavenaam afstand"
                  ,"start" => "0"
                  ,"rows" => "10"
              },
              {
                  "Content-Type" => Comm.REQUEST_CONTENT_TYPE_URL_ENCODED
              },
              method(:receiveWoonplaats)
          );
       } else {
          debug("Cancelled: NOT in NL");
          mLoading = false;
          mLoadingCount = 0;
       }


      } catch (ex) {
         mLoading = false;
         mLoadingCount = 0;
         debug("getWoonplaats error: "+ex.getErrorMessage());
      }
    }

    /******************************************************************
     * DRAW HELPERS 
     ******************************************************************/  
    function setStdColor (dc) {
      if (getBackgroundColor() == Gfx.COLOR_BLACK) {
         dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
      } else {
          dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
      }   
    }

    /******************************************************************
     * LABELS
     ******************************************************************/ 
    function drawSmallArrow (dc, track, bearing, xx, yy) {
        var x1_3 = 0.0;
        var y1_3 = 0.0;
        var x2_3 = 0.0;
        var y2_3 = 0.0;
        var x3_3 = 0.0;
        var y3_3 = 0.0;         
        var x4_3 = 0.0;
        var y4_3 = 0.0;    
        var x5_3 = 0.0;
        var y5_3 = 0.0;       
        var xoffset = 0;
        var yoffset = 0;
        var angle;

        // Radias of the circle and arrows


        var r = Math.round(mSH/66);

        // angle of the compass, point to north     
        if (track!=null) {
          angle = - (track* _180_PI) - 90;      
        } else {
          angle = - 315 - 90;
        }  
               
        var l  = 1;
        var l1 = .25;
                                               	                    
        if ((bearing!=null) && (track!=null)) {
          // heading to next way point
          // angle = (track - bearing)*_180_PI - 90;
          angle = (-track + bearing)*_180_PI - 90;
          l = 0.00;
          l1 = 0.80;
          var l2 = 1.00;
          
          var x =  r * Math.cos(angle*_PI_180) * l ;
          var y =  r * Math.sin(angle*_PI_180) * l ;  
 
          x1_3 = Math.round(x + r * Math.cos((angle+90)*_PI_180) * l1);
          y1_3 = Math.round(y + r * Math.sin((angle+90)*_PI_180) * l1); 
              
          x2_3 = Math.round(r * Math.cos(angle*_PI_180) * l2);
          y2_3 = Math.round(r * Math.sin(angle*_PI_180) * l2);
          
          x3_3 = Math.round(x + r * Math.cos((angle-90)*_PI_180) * l1);
          y3_3 = Math.round(y + r * Math.sin((angle-90)*_PI_180) * l1);   
          
          x4_3 = Math.round(r * Math.cos((angle)*_PI_180) * (-l2));
          y4_3 = Math.round(r * Math.sin((angle)*_PI_180) * (-l2));      
          
          x5_3 = Math.round(r * Math.cos((angle)*_PI_180) * 0.15);
          y5_3 = Math.round(r * Math.sin((angle)*_PI_180) * 0.15);       
         }     
       
        xoffset = xx;
        yoffset = yy;
        
        ////////////////////////////////////////////////////////////////// 
        // Circle around arrows 
        dc.setPenWidth(2);
        if (getBackgroundColor() == Gfx.COLOR_BLACK) {
          dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT); 
        } else {
          dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT); 
        } 
        dc.drawCircle(xoffset, yoffset, r);
              
        ////////////////////////////////////////////////////////////////// 
        // bearing        
        if ((bearing != null)) {
          if (getBackgroundColor() == Gfx.COLOR_BLACK) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT); 
          } else {
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT); 
          } 
          dc.setPenWidth(3);
          dc.drawLine(x5_3+xoffset,y5_3+yoffset, x4_3+xoffset,y4_3+yoffset);    

          dc.setPenWidth(1);     
          dc.fillPolygon([[x1_3+xoffset,y1_3+yoffset],[x2_3+xoffset,y2_3+yoffset],[x5_3+xoffset,y5_3+yoffset]]);   
          dc.fillPolygon([[x2_3+xoffset,y2_3+yoffset],[x3_3+xoffset,y3_3+yoffset],[x5_3+xoffset,y5_3+yoffset]]);  
        }
    }

    function fitString (dc, f, s, extra) {
      var ss = s;
      var addElipses = false;

      while (dc.getTextDimensions(ss, f)[0]>mW-XMARGING-XMARGING-extra) {
        ss = ss.substring(0, ss.length()-1);
        addElipses = true;
      }
      if (addElipses) {
        ss = ss.substring(0, ss.length()-2);
        ss = ss + "...";
      }

      return ss;
    }

    function drawLabel (dc, n, s, dir, distance) {
      try {
          var x = mW - XMARGING-XMARGING;
          var h = dc.getTextDimensions("X",  Gfx.FONT_GLANCE_NUMBER);
          x = XMARGING + x/2;
          var f = Gfx.FONT_GLANCE_NUMBER;
          var y = YMARGING - h[1]/2;

          if (mSH<790) {
            y = YMARGING - h[1];
          }

          if (n>0) {
             y = y + 4;
           }
          if (n>1) {
            y = y + h[1];
            f = Gfx.FONT_GLANCE;
            y = y + 4;
          }
          if (n>2) {
            y = y + h[1];
          }
          if (n>3) {
            y = y + h[1];
          }      
          if (n>4) {
            y = y + h[1];
          }      

          setStdColor(dc);
          var extra = 0;
          if (dir!=null) {
            s = "   "+s; // ruimte maken voor arrow
          }
          var ss = fitString(dc, f, s, extra);
          dc.drawText(x, y, f, ss, Gfx.TEXT_JUSTIFY_CENTER);

          if ((mTrack!=null) && (dir!=null)) {
            x = x - dc.getTextDimensions(ss,  Gfx.FONT_GLANCE)[0]/2;
            drawSmallArrow(dc, mTrack, dir, x, y+h[1]/2);
          }
      } catch (ex) {

      }
    }

    function drawLabels (dc) {
      if (_csInNL) {
        drawLabel(dc, 1, mLabel1, null, null);
        drawLabel(dc, 2, mLabel2, null, null);
        drawLabel(dc, 3, mLabel3, null, null);
      }
    }

    function drawStatus (dc) {
      var h = dc.getTextDimensions("X",  Gfx.FONT_GLANCE);
      setStdColor(dc);

      dc.setPenWidth(1);
      dc.drawLine(XMARGING, mH-h[1], mW-2*XMARGING, mH-h[1]);
      var dd;


      if (mLastWiki!=null) {
        var v2 = "";
        var v3 = "";
        v2 = mLastWiki.hour.format("%02d")+":"+mLastWiki.min.format("%02d");
        
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var v1 = now.hour.format("%02d")+":"+now.min.format("%02d");

        if (mLastWikiLat!=null) {
          dd = calcDistance(mLastWikiLat, mLastWikiLon);
          v3 = " ("+Math.round(dd[0]).format("%i")+"m)";
        }

        dc.drawText(XMARGING     , mH-h[1]/1.4, Gfx.FONT_TINY, v1                , Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(mW - XMARGING, mH-h[1]/1.4, Gfx.FONT_TINY, "UPDATED: "+v2+v3, Gfx.TEXT_JUSTIFY_RIGHT);
      } else {
        dc.drawText(XMARGING, mH-h[1]/1.4, Gfx.FONT_TINY, "TAP TOP OF THE FIELD TO UPDATE", Gfx.TEXT_JUSTIFY_LEFT);
      }

    }

    /******************************************************************
     * COMPASS 
     ******************************************************************/  
    function drawCompass (dc) {
        var track     = mTrack;
        var bearing   = mHome;

        var r = 35;
        var xoffset = mW - r - 10;
        var yoffset = mH - r - 50;     
       
        ////////////////////////////////////////////////////////////// 
        // COMPASS
        try {
          // Compass circle
          
          //dc.setPenWidth(3);
          //dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
          //dc.drawCircle(xoffset, yoffset, r+4);
          //dc.setPenWidth(1);
          //dc.drawCircle(xoffset, yoffset, r-27);
          
          var angle = 0;  
          if (track!=null) {
            angle = - (track* _180_PI) - 90;        
          } else {
            if (bearing!=null) {
              angle = (bearing* _180_PI)  - 360 - 90;
            } 
          }  
                  
          var l;
          var l1;

          for (var j=1; j<2; j++) {
            // 0 = Inner roos, 1 = outer roos
            if (j==1) {
              l  = 1.0;
              l1 = 0.25 ;
            } else {
              l  = 0.55;
              l1 = 0.20;
            }
            for (var i=1; i>=0 ; i--) {

             
             var a=0;
              var b=0;
              //if (j==1) {
                a = angle + i * 180.0;
                b = 90;
              //} else {
              //  a = angle + 45 + i * 90;
              //  b = 20;
              //}

              var x1_1 = Math.round(r * Math.cos(a*_PI_180) * l);
              var y1_1 = Math.round(r * Math.sin(a*_PI_180) * l);    
              var x2_1 = Math.round(r * Math.cos((a+b)*_PI_180) * l1);
              var y2_1 = Math.round(r * Math.sin((a+b)*_PI_180) * l1); 
              var x3_1 = Math.round(r * Math.cos((a-b)*_PI_180) * l1);
              var y3_1 = Math.round(r * Math.sin((a-b)*_PI_180) * l1);

              dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
              if (j==1) {
                if (i==0) {
                  dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_TRANSPARENT);
                }
                if (i==2) {
                  dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                }
              }

              dc.fillPolygon([
                            [x1_1+xoffset,y1_1+yoffset]
                            ,[x2_1+xoffset,y2_1+yoffset]
                            ,[xoffset,yoffset]
                            ]);
            
              dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
              if (j==1) {
                if (i==0) {
                  dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                }
                if (i==2) {
                  dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                }
              }

              dc.fillPolygon([
                            [x1_1+xoffset,y1_1+yoffset]
                            ,[x3_1+xoffset,y3_1+yoffset]
                            ,[xoffset,yoffset]
                            ]);
          

              if (getBackgroundColor() == Gfx.COLOR_BLACK) {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
              } else {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
              } 
          
              dc.setPenWidth(2);   
              dc.drawLine(x1_1+xoffset,y1_1+yoffset,x2_1+xoffset,y2_1+yoffset);
              dc.drawLine(x3_1+xoffset,y3_1+yoffset,x1_1+xoffset,y1_1+yoffset);
            }
          }
        } catch (ex) {
          debug("drawwind compass error: "+ex.getErrorMessage());
        }
    }

     /******************************************************************
     * WIKI
     ******************************************************************/   
    function fitString2 (dc, f, s, extra) {
      var ss = s;
      var addElipses = false;

      while (dc.getTextDimensions(ss, f)[0]>mW-XMARGING-extra) {
        ss = ss.substring(0, ss.length()-1);
        addElipses = true;
      }
      if (addElipses) {
        ss = ss.substring(0, ss.length()-2);
        ss = ss + "...";
      }

      return ss;
    }

    function drawWiki(dc) { 
      try {
        if (mWiki==null) {
          return;
        }

        var m = mWiki.size();
        var offsetY = 0;
        var h = dc.getTextDimensions("X  ",  Gfx.FONT_GLANCE);

        var yy  = h[1]*4;
        if (!_csInNL) {
          yy = 2;
        }

        var w     = mW - XMARGING;
        var xx    = XMARGING;
        var mm    = Math.round((mH - yy)/(h[1]*2));
        var short = mm - 2;

        if (m>mm) {
          m = mm;
        }

        offsetY = 5;
        var first = true; 
        for (var i=0; i<m; i+=1) {
          if (mWiki[i]!=null) {

            if (first) {
              if (_csInNL) {
                dc.drawLine(xx, yy-8, xx+w-XMARGING, yy-8);
              }
              first = false;
            }

            var s;
            var extra = 25;

            if (mH>700) {
              if (i>short) {
                extra = 110;
              }
            }

            setStdColor(dc); 
            var y = yy+(i*2*h[1])+offsetY;
            s = fitString2(dc, Graphics.FONT_SMALL, mWiki[i]["t"], extra);
            dc.drawText( xx, y, Graphics.FONT_SMALL, s, Graphics.TEXT_JUSTIFY_LEFT);
          
            setStdColor(dc); 
            drawSmallArrow(dc, mTrack, mWiki[i]["a"], XMARGING+Math.round(mSH/66), y+h[1]*1.3);
            s = mWiki[i]["des"];
            if (s.length()==0) {
              s = mWiki[i]["t"];
            }

            s = fitString2(dc, Graphics.FONT_TINY, mWiki[i]["d"].format("%i")+"m, "+s, extra );
            dc.drawText(xx+h[0]  , y+h[1], Graphics.FONT_TINY , s, Graphics.TEXT_JUSTIFY_LEFT);
          }
        
        }
      } catch (ex) {
       debug("drawWiki error: "+ex.getErrorMessage());
      }
    }

     /******************************************************************
     * INFO BOX 
     ******************************************************************/   
    function drawBox(dc, bgCol, fgCol, fgColS, line2) {
      try {
        var x = XMARGING;
        var y;
        var h;
        var hh = dc.getTextDimensions("X", mSF1)[1];
        var w = mW - XMARGING*2;

        y = mH - hh * 2.5;
        h = hh * 1.5;


        dc.setColor(bgCol, bgCol);
        dc.fillPolygon(
                         [                       
                          [x      , y]
                         ,[x + w  , y]
                         ,[x + w  , y + h]
                         ,[x     ,  y + h]
                         ]
                    );

        dc.setColor(Gfx.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);      
        dc.setPenWidth(2);
        dc.drawLine(x, y, x + w, y);
        dc.drawLine(x+w, y, x+w, y+h);
        dc.drawLine(x+w, y+h, x, y+h);
        dc.drawLine(x, y+h, x, y);

        dc.setColor(fgCol, Graphics.COLOR_TRANSPARENT);    
        dc.drawText(mW/2, y + hh/4, mSF1, line2.toUpper(), Gfx.TEXT_JUSTIFY_CENTER);

      } catch (ex) {
        debug("drawRadarFirst error: "+ex.getErrorMessage());
      }
    }

    function drawInfoBox(dc) {
      var bgCol = Gfx.COLOR_GREEN;
      var fgCol = Gfx.COLOR_BLACK;
      var fgColS = Gfx.COLOR_WHITE;
      var line2 = "";
      var show = false;

      // Loading
      if ( (mLoading) && (mLoadingCount>=0) ) {
        bgCol = Gfx.COLOR_WHITE;
        fgCol = Gfx.COLOR_BLACK; 
        fgColS = null;                             
        line2 = "Loading... "+mLoadingCount + "s";
        show = true;
      }   

      if (mCurrentLocation==null) {
        bgCol = Gfx.COLOR_RED;
        fgCol = Gfx.COLOR_WHITE; 
        fgColS = null;                             
        line2 = "WAITING FOR LOCATION";
        show = true;
      }  


      // GPS Signaal
      if (mGpsSignal<=2) {
        bgCol = Gfx.COLOR_RED;
        fgCol = Gfx.COLOR_WHITE; 
        fgColS = null;         
        line2 = "WAITING FOR GPS SIGNAL";
        show = true;
      }
  

      // Telefoon verbonden
      if ( !mConnectie ) {
        bgCol = Gfx.COLOR_RED;
        fgCol = Gfx.COLOR_WHITE; 
        fgColS = Gfx.COLOR_BLACK;                           
        line2 = "NO PHONE CONNECTION";
        show = true;
      } 

      // Loaderror  
      if ( (mLoadError.length()>0) ) {
        bgCol = Gfx.COLOR_RED;
        fgCol = Gfx.COLOR_WHITE; 
        fgColS = Gfx.COLOR_WHITE;                           
        line2 = mLoadError;
        show  = true;
      }  

      // Show Box

      if (show) {
        drawBox(dc, bgCol, fgCol, fgColS, line2);
        setStdColor(dc);
      }

    }

    /******************************************************************
     * TIMERS 
     ******************************************************************/  
    var mQueuIndex = 0;
    var mQueue     = new[3];
    var mQueuePause = false;

    function pushQueue(s) {
      var skip = false;

      // ontdubbel
      var n = mQueue.size();
      for (var i=0; i<n; i++) {
        var ss = mQueue[i];
        if ((ss!=null) && (ss.equals(s))) {
          skip = true;
        }
      }
    
      // toevoegen
      if (!skip) {
        n = mQueue.size();
        if (mQueuIndex<n) {
          //debug("push index "+mQueuIndex+", size: "+n);
          mQueue [mQueuIndex] = s;
          mQueuIndex++;
        } else {
          //debug("Queue overflow: "+s);
        }
      } else {
        //debug("Queue already in queu: "+s);      
      }
    }

    function popQueue() {
      if (mQueuePause) {
        return null;
      }

      var result = mQueue[0];

      if (result!=null) {
        if (mQueuIndex>0) {
          mQueuIndex--;
        }
        var m = mQueue.size();
        for (var i=1; i<m; i++) {
          mQueue[i-1] = mQueue[i];
        }
        mQueue[m-1] = null;
      }

      return result;
    }

    function handleQueu () {
      if (mLoading) {
        return;
      }

      if (mCurrentLocation==null) {
        return;
      }

      var q = popQueue();
      if (q!=null) {
        if (q.equals("woonplaats")) {
          getWoonplaats();
        }
        if (q.equals("wiki")) {
          getWiki(25);
        }    
      }
    }

    function every5Minutes() {
      var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
      debug("EveryMinute "+time.min+" ====================================================");

      if ((mH>200) || (!_csInNL)) {
        pushQueue("wiki");
      }
      if (_csInNL) {
        pushQueue("woonplaats");
      }
    }

    function restartTimers() {
      mLastMinute = 0;
      killComm();
      mQueuIndex = 0;
      var n = mQueue.size();
      for (var i=0; i<n; i++) {
        mQueue[i] = 0;
      }
      mQueuePause = false;
      every5Minutes();
    }

    function execTimer() {
      try {
        if (mCurrentLocation==null) {
          return;
        }

        var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        if (mLastMinute!=time.min) {
           debug("execTimer: "+time.min);
           try {

               if ((mLastMinute==0) || ((time.min - Math.floor(time.min/5) * 5)==0))  {
                every5Minutes();
               }

             
           } finally {
             mLastMinute = time.min;
           }
        }
      } catch (ex) {
         debug("execTimer error: "+ex.getErrorMessage());
      }
      
      try {
        handleQueu ();
      } catch (ex) {
        debug("execTimer handle queue error: "+ex.getErrorMessage());
      }
    }
    
    /******************************************************************
     * COMPUTE 
     ******************************************************************/  

    function clearLabels () {
      mLabel1 = "";
      mLabel2 = ""; 
      mLabel3 = "";
      mLabel4 = "";
      mLabel5 = "";
    }

    function addLabel (s) {
      if (
          (mLabel1.find(s)==null) &&
          (mLabel2.find(s)==null) &&
          (mLabel3.find(s)==null) &&
          (mLabel4.find(s)==null) &&
          (mLabel5.find(s)==null) 
         ) {
         if (mLabel1.length()==0) { mLabel1 = s; return; }
         if (mLabel2.length()==0) { mLabel2 = s; return; }
         if (mLabel3.length()==0) { mLabel3 = s; return; }
         if (mLabel4.length()==0) { mLabel4 = s; return; }
         mLabel5 = s; 
      }    
    }

    function setLabels () {
      try {
        clearLabels();

        if (!_csInNL) {
          return;
        }

        if (! mGemeente.equals("") )  {

            var ge = mGemeente;
            var wo = mWoonplaats;
            var wi = mWijk;
            var bu = mBuurt;

            // geen wijk, maar wel een buurt
            if (wi.length()==0) {
              wi = bu;
              bu = "";
            }

            // wijk = buurt
            if (wi.equals(bu)) {
              bu = "";
            }  

            // buurt = woonplaats
            if (bu.equals(wo)) {
              bu = "";
            } 

            // buur = gemeente
            if (bu.equals(ge)) {
              bu = "";
            } 

            // wijk = woonplaats
            if (wi.equals(wo)) {
              wi = "";
            } 

            // wijk = gemeente
            if (wi.equals(ge)) {
              wi = "";
            } 

            // woonplaats = gemeente
            if (wo.equals(ge)) {
              wo = "";
            }  

            // opschuiven
            if (wo.length()==0) {
              wo = wi;
              wi = bu;
              bu = "";
            }

            if (wi.length()==0) {
              wi = bu;
              wi = "";
            }

            // samen nemen
            if ((ge.length()>0) && (wo.length()>0)) {
              if ( wo.length()+2+ge.length()+4<24 ) {
                ge = wo + ", " + ge + " ("+mProvincie+")";
                wo = "";
              } else {
                ge = ge + " ("+mProvincie+")";
              }
            }

            // opschuiven
            if (wo.length()==0) {
              wo = wi;
              wi = bu;
              bu = "";
            }

           // samen nemen
            if ((wo.length()>0) && (wi.length()>0)) {
              if ( wo.length()+2+wi.length()<24 ) {
                wo = wo + ", " + wi;
                wi = "";
              } 
            } 

            // opschuiven
            if (wi.length()==0) {
              wi = bu;
              bu = "";
            }

           // samen nemen
            if ((wi.length()>0) && (bu.length()>0)) {
              if (wi.length()+2+bu.length()<24) {
                wi = wi + ", " + bu;
                bu = "";
              } 
            } 

            addLabel(ge);
            addLabel(wo);
            addLabel(wi);
            addLabel(bu);
        }
      } catch (ex) {
        debug("setlabels error: "+ex.getErrorMessage());
      }
    }   

    function getLastKnownLocation(info) {
      /*
          return  new Position.Location( {
                 // Amsterdam
                //  :latitude  => 52.37445,
                //  :longitude => 4.89785,
                 // london
                  :latitude  => 51.50758,
                   :longitude => -0.16555,
                  :format    => :degrees
           });    
           */



      if (
          (info.currentLocation!=null) && 
          (info.currentLocation.toDegrees()[0].toNumber()!=0) 
          //(info.currentLocation.toDegrees()[1].toNumber()!=-94) // Garmin default
         ) 
     {
        Storage.setValue("lastknown_lat" , info.currentLocation.toDegrees()[0].toFloat());
        Storage.setValue("lastknown_long", info.currentLocation.toDegrees()[1].toFloat());
        return info.currentLocation;
      } else {
        var lat  = Storage.getValue("lastknown_lat");
        var long = Storage.getValue("lastknown_long");
        if ((lat!=null) && (long!=null)) {
          return  new Position.Location( {
                :latitude  => lat,
                :longitude => long,
                :format    => :degrees
              });
        } else {
          return  new Position.Location( {
                 // Amsterdam
                  :latitude  => 52.37445,
                  :longitude => 4.89785,
                 // london
                   //:latitude  => 51.50758,
                   //:longitude => -0.16555,
                  :format    => :degrees
           });      
        }     
      }
      return null;
    }

    function checkNotInNL () {
      _csInNL = quickTestNL();
      if (!_csInNL) {
        // resetWiki();
        clearAddress();
      }
    }

    function compute(info) {
      try {  
        if (mLoading) {
          mLoadingCount = mLoadingCount + 1;

          if (mLoadingCount>30) {
            killComm();
          }
        }

        setWikiHint();

        mSH = System.getDeviceSettings().screenHeight;
        mSW = System.getDeviceSettings().screenWidth;

        // laast bekende locatie
        mCurrentLocation = getLastKnownLocation(info);
        if (mCurrentLocation!=null) {
          _cslastpos = mCurrentLocation.toDegrees()[0].toString() + "," + mCurrentLocation.toDegrees()[1].toString();
          _cslat     = mCurrentLocation.toDegrees()[0].toString();
          _cslong    = mCurrentLocation.toDegrees()[1].toString();
        }

       // get GPS accuracy 
       if (info.currentLocationAccuracy  != null)  {
          mGpsSignal = info.currentLocationAccuracy;
       }   
                  
          
        // get track (=compass)      
        mTrack = null;     
        if (info.track  != null)  {
            mTrack = info.track;
        } 
        
        // bearing
        mBearing = null;
        if (info has :bearing) {
          if (info.bearing != null) {
            mBearing = info.bearing;  
          }
        }        

        setLabels();
        mConnectie = System.getDeviceSettings().phoneConnected;
        recomputeWiki();
        checkNotInNL();

        Storage.setValue("cslastpos" , _cslastpos);  
        Storage.setValue("cslat"     , _cslat);  
        Storage.setValue("cslong"    , _cslong);  
      } catch (ex) {
          debug("Compute error: "+ex.getErrorMessage());
      }                  
    }
    
    /******************************************************************
     * On Update
     ******************************************************************/  
    function handleTouch() {
      try {
        
        if (GlobalTouched>=0) {
          GlobalTouched = -1;
          if (mLoading) {
            killComm();
          } else {
            mLoadError = "";
            restartTimers();
          }
        }
      
      } catch (ex) {
        GlobalTouched = -1;
        debug("handleTouch error: "+ex.getErrorMessage());
      }
    }

    function onUpdate(dc) { 
       try {       
         mW = dc.getWidth();
         mH = dc.getHeight();
         //if (mH<790) {     
         // return;
         //}
         execTimer();
         handleTouch();
         _csInNL = quickTestNL();
         try {
           dc.setColor(getBackgroundColor() , getBackgroundColor() );  
           dc.clear();
           setStdColor(dc);

           if (_csInNL) {
             drawLabels(dc);
           }
           if ((mH>200) || (!_csInNL)) {
             drawWiki(dc);
           }
           if (mH>700) {
             drawCompass(dc);
           }        
           drawStatus (dc);   
           drawInfoBox(dc);
         } catch (ex) {
           debug("onUpdate draw error: "+ex.getErrorMessage());
         }    
      } catch (ex) {
        debug("onUpdate ALL error: "+ex.getErrorMessage());
     }
    }

}
