require 'httpclient'
require 'bbc/redux'

module BBC
  module Redux
    class Asset
      def firstpart
        @firstpart
      end
      def firstpart=(fp)
        @firstpart = fp
      end
    end
  end
end

class User < BroadcastEntity
  include DataMapper::Resource

	@@clients = {}

  property :id,            Serial
  property :name, 	       String,  :default => ''
  property :fullname,      String,  :default => ''
  property :redux_user,    String,  :default => ''
  property :password,      String,	:default => ''
  property :default_rp,    String,	:default => ''
  property :throttle,			 Integer, :default => 0
  property :last_download, DateTime
  property :last_checked,  DateTime

  has n, :boxsets
  has n, :programmes
	has n, :channels, :through => Resource

  def actionbar_title
    nil
  end

  def title
    nil
  end

	def client
		@@clients[redux_user] ||= begin
      puts "Logging in for #{redux_user}"
      BBC::Redux::Client.new(:username => redux_user, :password => redux_pass, :http => HTTPClient)
    end
	end

	def logout
		@@clients[redux_user].logout if @@clients[redux_user]
		@@clients[redux_user] = nil
	end

  def children
    @children ||= boxsets.reject { |b| b.destroyed? or b.rescinded? or b.seasons.count == 0 }.sort
  end

	def movies
		@movies ||= boxsets.first_or_create(:name => Boxset::MOVIES_NAME, :movie => true)
	end

  def kill!
		unless destroyed?
			boxsets.everyone.kill!
			self.destroy
		end
	end

  def redux_pass
    User.untangle(default_rp, EPOCH) || password
  end

  def credentials
    [name, User.untangle(password, EPOCH)]
  end

  def creds
    "!cReD:#{name}::#{User.untangle(password, EPOCH).hexEncode}:"
  end

	def chans(channeltype = Channel::TYPE_ALL)
		update_channels if channels.length == 0
		@chans ||= {}
		@chans[channeltype] ||= channels.select { |c| (c.channeltype & channeltype) > 0x00 }
	end

	def update_channels
	  client.channels.each do |ch|
	  	unless channels.first(:fullname => ch.display_name)
				c = Channel.first(:fullname => ch.display_name)
				channels << c if c
			end
		end
		self.save
	end

	def channelnames(channeltype = Channel::TYPE_ALL)
		@channelnames ||= {}
	  @channelnames[channeltype] ||= chans(channeltype).collect { |c| c.namesarray }.flatten
	end

	def find_channel(name)
		chs = chans.select { |c| c.namesarray.include?(name) }
		chs.first if chs.size > 0
	end

  def read_from_redux(url)
  	url = REDUX_URL + url unless url.match(/^https?\:\/\//)
  	resp = nil
  	begin
      puts ">>>> Reading from #{url}"
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(redux_user, redux_pass)
  		http = Net::HTTP.new(uri.hostname, uri.port)
 		  http.use_ssl = url.match(/^https\:\/\//)
  		resp = http.request(req)
  		url = resp['location']
  	rescue
  		resp = Net::HTTPResponse.new(500, 501, 502)
    end while resp.code == '302'
    resp
	end

	def update_boxsets(force_refresh = false)
	  if programmes.count > 0
	  	self.last_checked ||= EPOCH
      if force_refresh or self.last_checked < DateTime.now - 0.25
	     	puts "@@@@       Updating boxsets for #{fullname}, last updated > #{self.last_checked}"
        boxsets.reject { |b| b.rescinded? }.each do |boxset|
        	if boxset.movie?
        		boxset.children.each do |season|
        			boxset.educe(boxset.latest, season.name.to_searchterm)
        		end
        	else
	          boxset.educe(boxset.latest)
	        end
        end
        self.last_checked = DateTime.now
	      self.save
      end
    end
	end

	def clone_season(season)
		s = Season.create(season.attributes.merge(:id => nil, :rescinded => false))
    season.programmes.each do |prog|
			puts ">>>>> Now cloning #{prog.title}..."
      p = Programme.create(prog.attributes.merge(:id => nil, :user => self, :season => nil, :rescinded => false))
      s.acquire(p)
      p.save
    end
    s.save
    s
	end

  def clone_boxset(boxset)
  	puts ">>> Cloning #{boxset.name}..."
    b = Boxset.create(boxset.attributes.merge(:id => nil, :user => self, :rescinded => false))
    boxset.seasons.each do |season|
			s = clone_season(season)
			b.seasons << s
			s.save
    end
    self.save
    b.save
    b
  end

  def throttled?
  	self.last_download ||= EPOCH
  	DateTime.now - self.last_download < self.throttle/24.0
  end

  def record_download
  	(self.last_download = DateTime.now) and save
  end

  class << self

    def tangle(key, d = nil)
    	if key.length > 0
        d = (d || DateTime.now).to_time.utc.strftime('%H%d%m%Y%d%Y%m%H')
	      newkey = key.dup # same length
	      keyl = key.length - 1
	      for i in (0..keyl)
          newkey[i] = (key[i].ord ^ d[i % 20].ord).chr
	      end
	      newkey
	    end
    end

    alias_method :untangle, :tangle # does the same thing

    def find_keyed_user(key)
      @entangleds ||= {}
      u = @entangleds[key]
      puts ">>> k = #{key}"
      if u.nil?
        if key.match(/^([^\:]+)\:([^\:]+)$/)
          unless $1.blank? or $2.blank?
            name = $1.hexDecode
            pass = tangle($2.hexDecode, EPOCH)
            if u = User.first(:name => name)
							u.password = pass if u.password.blank?
            else
              u = User.new(:name => name, :redux_user => name, :password => pass)
              u.fullname = u.client.user.name
            end
           	u.save
            @entangleds[key] = u if u.password == pass
          end
        end
      else
        u.reload
      end
			puts ">>> Identified user '#{u.name}'" if u
      @entangleds[key]
    end

  end

end


