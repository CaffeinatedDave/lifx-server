require 'rubygems'
require 'sinatra'
require 'lifx'
require 'json'

set :port, 8999
set :bind, '0.0.0.0'

class Command
	attr_accessor :time, :light, :color, :duration, :repeat

	def initialize(time, light, color, duration, repeat)
		@time=time.to_i
		@light=light
		@color=color
		@duration=duration.to_f
		@repeat=repeat.to_i
	end

	def to_s
		s = "Changing " + @light + " to " + @color + " over " + @duration.to_s + " seconds at " + Time.at(@time).to_s + "."	
		if @repeat > 0 
			s += " Repeating in " + @repeat.to_s + " seconds."
		end
		s
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
	'off' => LIFX::Color.hsb(0, 0, 0),
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

get '/color' do 
	content_type :json
	$COLORS.to_json
end

get '/schedule' do
	{timeNow: Time.new.to_s, serverTick: Time.at($tick).to_s, schedule: $schedule}.to_json
end

get '/after/:seconds/:label/:color/:duration/:repeat' do
	time = Time.new.to_i + params[:seconds].to_i
	$schedule[time] += [Command.new(time, params[:label], params[:color], params[:duration], params[:repeat])]
	status 202
end

get '/after/:seconds/:label/:color/:duration/' do
	time = Time.new.to_i + params[:seconds].to_i
	$schedule[time] += [Command.new(time, params[:label], params[:color], params[:duration], 0)]
	status 202
end

get '/after/:seconds/:label/:color/' do
	time = Time.new.to_i + params[:seconds].to_i
	$schedule[time] += [Command.new(time, params[:label], params[:color], 0, 0)]
	status 202
end

$schedule = Hash.new([])

$tick = Time.new.to_i

sunriseBegin = Time.parse(Date.parse(Time.new.to_s).to_s + " 06:15:00").to_i
sunsetBegin = Time.parse(Date.parse(Time.new.to_s).to_s + " 22:30:00").to_i

if Time.new.to_i > sunriseBegin
	sunriseBegin += 86400

	if Time.new.to_i > sunsetBegin
		sunsetBegin += 86400
	end
end

$schedule[sunriseBegin] = [Command.new(sunriseBegin, 'all', 'yellow', 86400,  1800)]
$schedule[sunsetBegin] = [Command.new(sunsetBegin, 'all', 'off', 86400, 1800)]

Thread.new do 
	while true do
		while $tick < Time.now.to_i do
			if $schedule[$tick].size > 0
				events = $schedule[$tick]

				events.each do |event|
					STDOUT.puts "<Scheduler> :: " + event.to_s 

					selected = nil 
					if event.light != 'all'
						selected = [$client.lights.with_label(event.light)]
					end
					setLight(event.color, event.duration.to_f, selected) 
	
					# Are we repeating this?
					if event.repeat > 0 
						STDOUT.puts "Repeating event in " + event.repeat.to_s + " seconds"
						nextEvent = Command.new($tick + event.repeat, event.light, event.color, event.duration, event.repeat)
						$schedule[$tick + event.repeat] += [nextEvent]
					end
				end
				$schedule.delete $tick
			end
			$tick += 1
		end
		sleep 1
	end
end


