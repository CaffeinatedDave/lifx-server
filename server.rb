require 'rubygems'
require 'sinatra'
require 'lifx'
require 'JSON'

set :port, 8999

$client = LIFX::Client.lan
$client.discover!
STDOUT.puts "Discovered lights"

$COLORS = {
	'red' => LIFX::Color.red.with_brightness(0.7).with_saturation(0.7),
	'green' => LIFX::Color.green.with_brightness(0.7),
	'blue' => LIFX::Color.blue.with_brightness(0.7),
	'yellow' => LIFX::Color.yellow.with_brightness(0.7),
	'purple' => LIFX::Color.purple.with_brightness(0.7),
	'off' => LIFX::Color.hsbk(0, 0, 0, 2000),
}

$client.lights.each do |l|
	$COLORS[l.label] = l.color
end

def setLight(color, duration, lights) 
	lights ||= $client.lights
	lights.each do |l|
		l.set_color($COLORS[color], duration: duration)
	end
end

get '/lights' do
	list = ""
	$client.lights.each do |l|
		list << l.label
		list << "\r\n"
	end
	list
end

get '/label/all/:color' do
	setLight(params[:color], 0, nil)
	status 200
end

get '/label/:name/:color' do
	l = [$client.lights.with_label(params[:name])]
	setLight(params[:color], 0, l)
	status 200
end

get '/schedule/:time/:light/:color' do

end

get '/color/:name/:hue/:sat/:bri/:kel' do 
	503 if $COLORS.include? params[:name]

	h = params[:hue].gsub(/[^\d\.]/, '').to_f
	s = params[:sat].gsub(/[^\d\.]/, '').to_f
	b = params[:bri].gsub(/[^\d\.]/, '').to_f
	k = params[:kel].gsub(/[^\d\.]/, '').to_f
	$COLORS[params[:name]] = LIFX::Color.hsbk(h, s, b, k)
	status 200
end

get '/color/:name' do 
	404 unless $COLORS.include? params[:name] 	

	c = $COLORS[params[:name]]
	content_type :json
	{hue: c.hue, saturation: c.saturation, brightness: c.brightness, kelvin: c.kelvin}.to_json
end

get '/schedule' do
	{timeNow: Time.new.to_s, serverTick: Time.at($tick).to_s, schedule: $schedule}.to_json
end

get '/after/:seconds/:label/:color' do
	time = Time.new.to_i + params[:seconds].to_i
	$schedule[time] = {light: params[:label], color: params[:color]}
	status 202
end

$schedule = Hash.new(false)

$tick = Time.new.to_i

$schedule[$tick] = {light: 'Front Room', color: 'blue'}
$schedule[$tick + 1] = {light: 'Front Room', color: 'red'}
$schedule[$tick + 2] = {light: 'Front Room', color: 'Front Room'}

Thread.new do 
	while true do
		if $schedule[$tick] != false
			event = $schedule[$tick]
			STDOUT.puts Time.at($tick).to_s + " <Scheduler> :: Set " + event[:light] + " light to " + event[:color]
			selected = $client.lights
			if event[:light] != 'all'
				selected = [$client.lights.with_label(event[:light])]
			end
			setLight(event[:color], 1, selected) 
			$schedule.delete $tick
		end
		$tick += 1
		sleep 1
	end
end


