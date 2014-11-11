require 'rubygems'
require 'sinatra'
require 'lifx'
require 'JSON'

set :port, 8999
set :bind, '0.0.0.0'

class Command
   def initialize(id, name, addr)
      @cust_id=id
      @cust_name=name
      @cust_addr=addr
   end
end

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

get '/schedule/:time/:light/:color' do
end

get '/color/:name/:hue/:sat/:bri/:kel' do 
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

$schedule = Hash.new([])

$tick = Time.new.to_i

first = $client.lights.take(1).shift

$schedule[$tick] = [{light: first.label, color: 'blue', repeat: 0, duration: 1}]
$schedule[$tick + 1] = [{light: first.label, color: 'red', repeat: 5, duration: 0.5}]
$schedule[$tick + 2] = [{light: first.label, color: first.label, repeat: 5, duration: 0.5}]

sunriseBegin = Time.parse(Date.parse(Time.new.to_s).to_s + " 06:30:00").to_i
sunsetBegin = Time.parse(Date.parse(Time.new.to_s).to_s + " 22:00:00").to_i

if Time.new.to_i > sunriseBegin
	sunriseBegin += 86400

	if Time.new.to_i > sunsetBegin
		sunsetBegin += 86400
	end
end

$schedule[sunriseBegin] = [{light: 'all', color: 'yellow', repeat: 86400, duration: 1800}]
$schedule[sunsetBegin] = [{light: 'all', color: 'off', repeat: 86400, duration: 1800}]

Thread.new do 
	while true do
		if $schedule[$tick].size > 0
			events = $schedule[$tick]
			events.each do |event|
				STDOUT.puts Time.at($tick).to_s + " <Scheduler> :: Set " + event[:light] + " light to " + event[:color]
				selected = $client.lights
				if event[:light] != 'all'
					selected = [$client.lights.with_label(event[:light])]
				end
				setLight(event[:color], event[:duration], selected) 

				# Are we repeating this?
				if event[:repeat] > 0 
					STDOUT.puts "Repeating event in " + event[:repeat].to_s + " seconds"
					$schedule[$tick + event[:repeat]] += [event]
				end
			end
			$schedule.delete $tick
		end
		$tick += 1
		sleep 1
	end
end


