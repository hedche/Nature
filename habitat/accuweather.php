<?php
function realtime_weather($location=28143){
$apiURL = 'http://apidev.accuweather.com/currentconditions/v1/'.$location.'.json?language=en&apikey=YOUR_KEY';
$content = file_get_contents($apiURL);
$jsonObject = json_decode($content);
return $jsonObject[0];
}
?>
