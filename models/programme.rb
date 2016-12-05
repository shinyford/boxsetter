class Programme < BroadcastEntity
  include DataMapper::Resource

  property :id,       	Serial
  property :title_orig, String,  	:required => true, :length => 200
  property :desc_orig,  String,	  :required => true, :length => 2000
  property :pcrid_orig, String, 	:required => true
  property :pcrid,      String, 	:required => true
  property :date,       DateTime,	:required => true
  property :duration, 	Integer,	:required => true
  property :idx,      	Integer,	:required => true, :default => 1000000
  property :prepared,   Boolean,  :default => false
  property :reference,	String
  property :position,		Integer,	:default => 0
  property :viewed_at,  Integer,  :default => 0
  property :rescinded,  Boolean,  :default => false
  property :distrib, 		String, 	:default => 'bbcredux'

  belongs_to :season
	belongs_to :channel
	belongs_to :user

  alias_method :parent, :season

	@@image_url_templates = {
		'bbcredux' => 'http://g.bbcredux.com/programme/%s/download/image-640.jpg',
		'gomes' => 'http://www.gomes.com.es/h264/%s.jpg'
	}

	def orig
		@orig ||= user.client.asset(self.reference)
	end

	def children
	  @children ||= []
	end
  alias_method :viewable_children, :children

  def <=>(other)
    b = self.idx <=> other.idx
    b != 0 ? b : self.date <=> other.date
  end

  def title
  	get_title_and_desc unless @title
  	@title
  end

  def desc
  	get_title_and_desc unless @desc
  	@desc
  end

  def basictitle
  	get_title_and_desc unless @basictitle
  	@basictitle
  end

	def set_saved_at(p, d)
    if d > self.viewed_at
      self.position = p
  		self.viewed_at = d
  		self.save
  		season.set_saved_at(d)
    end
    return self.position, self.viewed_at
	end

  def filename
  	@filename ||= begin
			if movie?
				"(%d) %s" % [date.year, title]
			elsif season.name
				"%s - %s - E%02d %s" % [season.boxset.prefix, season.name, self.number, basictitle]
			else
				"%s - S%02dE%02d %s" % [season.boxset.prefix, season.number, self.number, basictitle]
			end
			.sanitise
		end
  end

  def broadcast_date
    @bdate ||= date.to_date
  end

	def addenda
    @addenda ||= begin
    	if movie?
    		"#{duration/60}mins (#{date.strftime('%Y')})"
    	else
		    "#{season.boxset.name + ', ' if title.match(/^#{season.boxset.name}/)}#{channel.fullname}\n#{date.strftime('%d %b %y %H:%M')} (#{duration / 60} mins)"
    	end
    end
	end

	def image_url
		@image_url ||= @@image_url_templates[self.distrib] % (self.reference || self.pcrid)
	end

  def image(imtype = :image)
    @transforms ||= {
      image: '', # 'w_640,h_360,c_fill/', 
      face: 'w_200,h_200,c_thumb,g_faces,r_max/' 
    }
    @images ||= {}
    @images[imtype] ||= "http://res.cloudinary.com/gomes/image/fetch/#{@transforms[imtype]}#{image_url}"
  end

	def chid
		season.chid
	end

  def boxsetter_url
    @boxsetter_url ||= "#{BXSTR_URL}/fetch/#{pcrid}.mp4"
  end

	def mp4_url(u = nil)
		u ||= user
		if distrib == 'bbcredux'
			u.record_download
      puts "Looking for #{filename}.mp4 ref #{reference}"
			u.client.asset(reference).h264_hi_url.end_point(filename + '.mp4')
		else
			"http://www.gomes.com.es/h264/#{filename}.mp4"
		end
	end

	def kill!
    self.destroy unless destroyed?
	end

  class << self

    def latest(progs)
      p = progs.first
      progs.each do |q|
        p = q if p.date < q.date
      end
      p
    end

    def from_redux(user, pathname)
      redux_url = pathname + '.json'
			if (data = user.read_from_redux(redux_url))
				if data and data.code == '200'
					item = JSON.parse(data.body)

					pcrid      = item['pcrid'].to_crid
					if pcrid
						pubdate    = DateTime.parse(item['when'])
						ch		     = user.chans.first(:name => item['service'])

						if ch and Programme.first(:pcrid => pcrid, :user => user).nil?
							prog = Programme.new(
								:title_orig => item['title'].sub(/^New\: /, ''),
								:desc_orig => item['description'],
                :pcrid_orig => item['pcrid'],
								:pcrid => pcrid,
								:date => pubdate,
								:duration => item['duration'].to_i,
								:user => user,
								:channel => ch,
								:reference => item['diskref']
							)

							boxset = Boxset.first_or_create(:name => Boxset::MOVIES_NAME, :user => user, :searchterm => '')
							boxset.acquire(Season.new(:channel => ch)) if boxset.seasons.length == 0
							boxset.seasons[0].acquire(prog)

							puts ">>> Created #{prog.title}"

							boxset.save
						end
					end
				end
			end
		end

		private

    def find_spurious_titles
      all.each do |p|
        if p.title == p.title_orig
          puts p.id.to_s + ': ' + p.title
          puts '***: ' + p.desc
          puts '***: ' + p.desc_orig
          puts ' '
        end
      end
      nil
    end

  end

  private

  def get_title_and_desc
    @desc = desc_orig.dup
    @title = title_orig.dup
    @basictitle = ''
    @ep = nil
    @part = nil

    if @title[-3..-1] == '...' and @desc.match(/^\.\.\.([^\.]+)\. (.*)$/)
      @desc = $2
      @title = title[0..-4] + ' ' + $1
    end

		while @desc.match(/^(New series|CBBC|NEW)\. (.*)$/)
			@desc = $2
		end


		while @desc.match(/^Brand new series - (.*)$/)
			@desc = $1
		end

		while @desc.match(/^(.*) (Also in HD.|\[[^\]]+\])$/)
			@desc = $1
		end

    if @desc.match(/^(\d+)\/(\d+)\. (.*)$/)
    	@part = $1 if $2 == '2'
      @desc = $3
    end
    if @desc.match(/^(.*)( -|,|\.) Part ([\w\d]+)[\.\:] (.*)$/)
    	@part = $3.downcase
      @desc = $1 + ': ' + $4
    end
    if @desc.match(/^Part (\w+): ([^\:]+): (.*)$/)
    	@part = $1.downcase
      @desc = $2 + ': ' + $3
    end
    if @desc.match(/^(.*), part ([^\.\:]+)\. (.*)$/)
    	@part = $2.downcase
      @desc = $1 + ': ' + $3
    end

    if @desc.match(/^([^\.\:]+)\: (.*)$/)
      @desc = $2
      @title = $1
    end

    while @title.match(/^(.*): (.*)$/) and $1 == season.boxset.name
    	@title = $2
    end

		if pcrid_orig.include?('#0')
			@part = '1'
		elsif pcrid_orig.include?('#1')
			@part = '2'
		end

    @basictitle = @title unless @title == season.boxset.name or @title == season.name
    if @part
    	@title += ',' if @title[-1].match(/(\w|\d)/)
    	@title += " part #{@part}"
    end

    unless movie?
      @ep = "#{number}/#{season.children.count}" unless @ep
      @title += ' (' + @ep + ')'
    end
  end

end

