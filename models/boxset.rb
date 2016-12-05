class Boxset < BroadcastEntity
  include DataMapper::Resource

  property :id,      			Serial
  property :name,         String,  	:default => ''
  property :searchterm,   String,  	:default => ''
  property :movie,      	Boolean,  :default => false
  property :rescinded,    Boolean,  :default => false
  property :position,			Integer,	:default => 0
  property :viewed_at,		Integer,	:default => 0

  has n, :seasons
  belongs_to :user

	alias_method :sire, :user
	alias_method :title, :name

  MOVIES_NAME = 'Movies'
	MOVIE_MATCH = /[ \(\[]((19|20)\d\d)[\)\]\.]/
	BOXSET_LIMIT = 300
	SLABSIZE = 100
	REPLACEMENTS = [
		'and', '&',
		'mr', 'mister'
	]

  def desc
		@desc ||= 'from redux'
  end

	def idx
		sire.children.index(self) + 1
	end

  def boxsetter_url
    @boxsetter_url ||= "#{BXSTR_URL}/boxset/#{self.id}"
  end

	def programmes
		@programmes ||= children.collect { |s| s.children }.flatten
	end

	def latest
		@latest ||= programmes.collect { |p| p.date }.max
	end

	def reset
		@children = nil
	end

	def renumber
		seasons.sort.each_with_index do |s, i|
			s.idx = (i+1)*10
		end
		seasons.save
		reset
	end

	def <=>(other)
		self.cfname <=> other.cfname
	end

	def children
		@children ||= seasons.reject { |s| s.destroyed? or s.rescinded? or s.children.length == 0 }.sort
	end

	def set_saved_at(d)
		if d > self.viewed_at
			self.viewed_at = d
			self.save
		end
	end

	def acquire(season)
		b = season.boxset
		unless b == self
			self.seasons << season
			self.save
			season.save
			reset
			unless b.nil?
				b.reset
				b.save
			end
		end
	end

	def cfname
		@cfname ||= name.downcase.sub(/^the /,'')
	end

	def prefix
		movie? ? "FILM" : name.sanitise
	end

  def chid
    @sample ||= children.sample
  	@sample.chid
  end

  def addenda
  	@addenda ||= if children.count == 1
			c = children.first.children.count
			"#{c} programme#{'s' unless c == 1}"
		else
			"#{children.count} seasons starting #{children.first.startdate.strftime('%Y')}"
		end
  end

  def duration
  	@duration ||= children.collect { |s| s.duration }.inject(:+)
  end

	def kill!
		unless destroyed?
			seasons.everyone.kill!
			self.destroy
		end
	end

	def is_second_part(asset, lastasset)
		asset.start.to_date == lastasset.start.to_date &&
		asset.start != lastasset.start &&
		asset.pcrid && lastasset.pcrid &&
		asset.pcrid.content == lastasset.pcrid.content
	end

	def get_data(since_date, term, replacements = REPLACEMENTS, channeltype = Channel::TYPE_ALL)
		replacements = replacements.clone
		offset = 0
		items = []
		data = nil # create in outer scope
		titles = [term, 'new: ' + term]

		lasta = nil
		ctr = 0
		begin
			search_params = {:q => term, :after => since_date - 1, :limit => SLABSIZE, :offset => offset, :channel => user.channelnames(channeltype)}
			search_params[:titleonly] = true unless movie?

			data = user.client.search(search_params)

			if data.total > 999
				if channeltype == Channel::TYPE_ALL
					items = get_data(since_date, term, replacements, Channel::TYPE_BBC)
					return items if items.size > 0

					items = get_data(since_date, term, replacements, Channel::TYPE_ITV)
					return items if items.size > 0

					return get_data(since_date, term, replacements, Channel::TYPE_OTH)
				else
					return [] # at this stage, give up entirely
				end
			end

			data.assets.each do |a|
				break if a.start < since_date
      	if (movie? and a.description.match(MOVIE_MATCH)) or (!movie? and titles.include?(a.name.to_searchterm))
					puts "Found: #{a.name} #{a.start}"
					begin
						a = user.client.asset(a.reference) if a.pcrid.nil?
					rescue Exception => e
						puts e
					end
					unless a.pcrid.nil?
						if !lasta.nil? and is_second_part(a, lasta)
							a.pcrid.content.concat('pt1')
							lasta.firstpart = a
						else
							items << a
						end
					end
				end

				lasta = a
			end

			offset += SLABSIZE
		rescue Exception => e
puts $!, $@
			break
		end while data.has_more?

		newterm = term

		while items.length == 0 and replacements.length > 0
			p1 = replacements.shift
			p2 = replacements.shift

			newterm = term.repword(p1, p2)
			if newterm != term
				items = get_data(since_date, newterm, replacements)
				break if items.length > 0
			end

			newterm = term.repword(p2, p1)
			if newterm != term
				items = get_data(since_date, newterm, replacements)
				break if items.length > 0
			end

		end

		if newterm != term and items.length > 0
			self.searchterm = newterm
			self.save
		end

		items
	end

  def educe(since_date = nil, term = nil, season = nil)
  	term ||= searchterm
  	title = term.titleise

  	unless term.blank?
			since_date ||= EPOCH

			reset

			items = get_data(since_date, term)

			return false unless items.count > 0 and items.first.start > since_date

			if movie?
				filterati = {}
				newitems = []

				items.each do |item|
					next unless item.description.match(MOVIE_MATCH)
					item.send(:start=, DateTime.new($1.to_i, 1, 1, 12, 0, 0))
					if filterati[$1].nil? or filterati[$1].duration < item.duration
						filterati[$1] = item
					end
				end

				filterati.each_pair do |year, item|
					newitems << item
					if item.firstpart
						item.firstpart.pcrid.content.concat('#0')
						item.firstpart.send(:start=, item.start - 1.0/24.0)
						newitems << item.firstpart
					end
				end

				season ||= seasons.first_or_create(:name => title, :channel => Channel.first)
				items = newitems.sort { |a,b| a.start <=> b.start }
			end

			limit = seasons.collect { |s| s.programmes.count }.inject(:+) || 0 # count the programmes already held

			puts '>>>>>>>'
			items.uniq { |i| i.pcrid }.each do |item|
				puts "#{item.start.strftime('%Y')}: '#{item.title}': #{item.description} >>#{item.pcrid}<<"
			end

			items.uniq { |i| i.pcrid }.each do |item|
				next if item.start < since_date
				next if item.pcrid.nil? or item.pcrid.content.blank?
				next if item.description.match(/\[[^\]]*SL[^\]]*\]/) # no signed shows
				next unless ch = user.find_channel(item.channel.name)

				pcrid = item.pcrid.content.to_crid
				next if Programme.first(:pcrid => pcrid, :user => user)

				break if (limit += 1) >= BOXSET_LIMIT

				puts "Found '#{item.description[0..40]}..., #{ch.fullname}"

				prog = Programme.first_or_create(:pcrid => pcrid, :user => user) # this will replace any repeats with the first broadcast on new educes
				prog.attributes = {
					:title_orig => item.name.sub(/^New\: /, ''),
					:desc_orig => item.description,
					:pcrid_orig => item.pcrid.content,
					:pcrid => pcrid,
					:date => item.start,
					:duration => item.duration,
					:user => user,
					:channel => ch,
					:reference => item.reference
				}
				prog.save

				self.name = prog.title_orig if self.name.blank?

				if !movie?
					season ||= seasons.find { |s| s.spans?(prog) }
					unless season
						season = Season.new(:channel => ch)
						season.idx = self.children.last.idx + 10 if self.children.count > 0 and self.children.last.idx < 1000
						season.save
					end
				end

				puts ">>>Season name: #{season.name}<<< #{seasons.include?(season)}"
				self.acquire(season) unless seasons.include?(season)
				season.acquire(prog)
				puts ">>>Season name: #{season.name}<<< #{seasons.length} #{season == seasons.last} #{season.programmes.count} #{seasons.last.programmes.count}"
			end
		end

		if seasons.length == 0
			self.destroy
			false
		else
			self.save
		end
  end

  class << self

		def educe(title, user, movie = false)
			searchterm = title.gsub('+', ' ').to_searchterm
			puts ">>>> Boxset searchterm = '#{searchterm}' from '#{title}' (#{movie})"
			since_date = nil

			if movie
				boxset = first_or_create(:name => MOVIES_NAME, :user => user, :movie => true)

				season = Season.find { |s| s.searchterm == searchterm and s.boxset.user == user }
				if season.nil?
					if season = Season.find { |s| s.searchterm == searchterm }
						if season.boxset.user != user
							since_date = season.rescinded? ? EPOCH : season.boxset.user.last_checked
							season = user.clone_season(season)
							boxset.seasons << season
							boxset.save
							season.save
						end
					end
				end

				boxset.searchterm = searchterm
			else
				boxsets = all(:searchterm => searchterm, :movie => false)
				if boxsets.count > 0
					boxset = boxsets.first(:user => user) || boxsets.first
					boxset = user.clone_boxset(boxset) unless boxset.user == user
				else
					boxset = create(:searchterm => searchterm, :user => user, :movie => false)
				end
			end

			boxset if boxset.educe(since_date)
		end

  end

end

