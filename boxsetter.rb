#! /usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'sinatra/cookies'
require 'thin'
require 'common'

enable :session

def authorised?
  @auth = Rack::Auth::Basic::Request.new(request.env)
  @user = (User.find { |u| @auth.credentials == u.credentials } if @auth.provided? and @auth.basic? and @auth.credentials)
end

def authorised!
  if authorised?
	  puts "#### #{@user.name} is accessing Boxsetter..."
	  @user.update_boxsets(true) if request.params['refresh'] == 'update'
  else
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, "Not authorised\n"
  end
end

def secure?
  request.env['HTTP_BOXSETTERSECURE'] == 'true'
end

def secure!
  halt 401, "Not secure enough - try https!\n" unless secure?
end

def erbidacious(obj, format)
  obj = obj.parent while obj.destroyed?
  @objects = obj.viewable_children.select_collect { |o|
    o.props if o.instance_of?(Programme) or o.viewable_children.count > 0
  }
  if format == 'json'
    content_type :json
    erb :objects_json
  else
    content_type :html
    erb :objects_html
  end
end

not_found do
  # halt(404, "Boxsetter doesn't know this ditty\n") unless request.path.match(/^\/images\/.*\/([^\/]+?)(-([a-z]+))?\.jpg$/)
  # type = ($3.blank?) ? 'image' : $3
  # puts "@@@ #{type} request for pcrid #{$1}"

  # filename = Programme.first(:pcrid => $1).send("generate_#{type}".to_sym)
  # puts "@@@ File name for #{type}: #{filename}"

  # content_type 'image/jpeg'
  # halt 200, File.open(filename, 'r') { |f| f.read }
  puts "Not known path: #{request.path}"
end

after do
  @user.logout if @user
end

get '/boxsetter.gomes.com.es.html' do
  File.read(File.join('public', 'boxsetter.gomes.com.es.html'))
end

get '/test' do
  secure!
  'OK'
end

get '/login' do
  secure!
  authorised!
  'OK'
end

get '/boxsets.?:format?' do |format|
  secure!
  authorised!

  searchterm = request.params['search']
puts "PARAMS>>> #{request.params}"
  if !searchterm.blank? and b = Boxset.educe(searchterm, @user, request.params['type'] == 'movie')
    @user.boxsets << b unless @user.boxsets.include?(b)
 	  @user.save
  end

  erbidacious(@user, format)
end

get '/boxset/:id/delete.?:format?' do |id, format|
  secure!
  authorised!

  halt 404, "Boxset #{id} not found\n" unless boxset = @user.boxsets.get(id)
  boxset.kill!
  erbidacious(boxset, format)
end

get '/boxset/:id.?:format?' do |id, format|
  secure!
  authorised!

  halt 404, "Boxset #{id} not found\n" unless boxset = @user.boxsets.get(id)

 	searchterm = request.params['search']
  if request.params['delete'] == 'now'
    boxset.rescinded = true
    boxset.save
    halt 200, 'OK'
  elsif !searchterm.blank?
    boxset.educe(EPOCH, searchterm)
	  erbidacious(@user, format)
  elsif request.params['join']
		ids = request.params['join'].split(',')
		if ids.length > 1 and (season = boxset.seasons.get(ids.first.to_i))
			ids[1..-1].each do |id|
				if id[0] == 'P'
					a = Programme.get(id[1..-1].to_i)
				else
					a = boxset.seasons.get(id.to_i)
					a = a.programmes if a
				end
				season.acquire(a) if a
			end
		end
	  erbidacious(@user, format)
	else
	  erbidacious(boxset, format)
	end
end

post '/boxset/:id' do |id|
  secure!
  authorised!

  halt 404, "Boxset #{id} not found\n" unless boxset = @user.boxsets.get(id)
	params['season'].each_pair do |sid, hash|
		s = boxset.seasons.get(sid.to_i)
		if s.title != hash['editable']
			s.name = hash['editable']
			s.save
		end
	end
  erbidacious(boxset, nil)
end

get '/boxset/:bid/season/:num/delete.?:format?' do |bid, num, format|
  secure!
  authorised!

  halt 404, "Season #{num} of boxset #{bid} not found\n" unless season = @user.boxsets.get(bid).children[num.to_i - 1]
  season.kill!
  erbidacious(season, format)
end

get '/boxset/:bid/season/:num.?:format?' do |bid, num, format|
  secure!
  authorised!

	boxset = @user.boxsets.get(bid)
  halt 404, "Season #{num} of boxset #{bid} not found\n" unless boxset and season = boxset.children[num.to_i - 1]
  if request.params['delete'] == 'now'
    season.rescinded = true
    season.save
    halt 200, 'OK'
  else
		searchterm = request.params['search']
		if !searchterm.blank?
	    boxset.educe(EPOCH, searchterm, season)
		  erbidacious(@user, format)
		else
			erbidacious(season, format)
  	end
	end
end

post '/boxset/:bid/season/:num' do |bid, num|
  secure!
  authorised!

  halt 404, "Season #{num} of boxset #{bid} not found\n" unless season = @user.boxsets.get(bid).children[num.to_i - 1]
	params['programme'].each_pair do |pid, hash|
		p = season.programmes.get(pid.to_i)
		if p.desc_orig != hash['editable']
			if hash['editable'].blank?
				p.kill!
			else
				p.desc_orig = hash['editable']
				p.save
			end
		end
	end
	erbidacious(season, nil)
end

get '/fetch/:pcrid/delete.?:format?' do |pcrid, format|
  secure!
  authorised!

  halt 404, "Programme #{pcrid} not found\n" unless prog = @user.programmes.first(:pcrid => pcrid)
  prog.kill!
  erbidacious(prog, format)
end

get '/fetch/:pcrid.mp4' do |pcrid|
  secure!
  authorised!

	halt(404, "Programme #{pcrid} not found\n") unless prog = @user.programmes.first(:pcrid => pcrid)
	if request.params['position']
		p, d = prog.set_saved_at(request.params['position'].to_i, request.params['viewedat'].to_i)
    halt 200, {:status => 200, :position => p, :viewed_at => d}.to_json 
  elsif request.params['delete'] == 'now'
    prog.rescinded = true
    prog.save
    halt 200, 'OK'
  else
  	puts "Got here..."
		searchterm = request.params['search']
		if !searchterm.blank?
	  	prog.season.boxset.educe(EPOCH, searchterm, prog.season)
		  erbidacious(@user, 'json')
	  else
	    halt(403, "User #{@user.fullname} forbidden from accessing video at this time") if @user.throttled?
			url = prog.mp4_url
			@user.record_download
	    if request.params['format'] == 'json'
	    	json = {:status => 200, :destination => url, :position => prog.position}.to_json
	    	puts 'JSON = ' + json
	      halt 200, json
	    else
	      puts "Okay, transferring to #{url}"
	      redirect url
	    end
		end
  end
end

get '/search/:searchterm.?:format?' do |searchterm, format|
  secure!
  authorised!

  if !searchterm.blank? and b = Boxset.educe(searchterm, @user)
    @user.boxsets << b
    @user.save
  end
  erbidacious(@user, format)
end

get '/movie' do
  secure!
  authorised!

  Programme.from_redux(@user, $1) if params['url'].match('^https?:\/\/g\.bbcredux\.com(\/programme\/.*)$')
  redirect back
end

