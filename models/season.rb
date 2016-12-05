class Season < BroadcastEntity
  include DataMapper::Resource

  property :id,       	Serial
  property :idx,				Integer, 	:default => 1000000
	property :name,				String
  property :rescinded,  Boolean, 	:default => false
  property :position,		Integer,	:default => 0
  property :viewed_at,	Integer,	:default => 0

  has n, :programmes
  belongs_to :boxset
  belongs_to :channel

	alias_method :parent, :boxset

  def boxsetter_url
    @boxsetter_url ||= "#{BXSTR_URL}/boxset/#{boxset.id}/season/#{self.number}"
  end

	def searchterm
		@searchterm ||= (movie? ? title.to_searchterm : boxset.searchterm)
	end

  def reset
  	[
  		:@children, :@number, :@identifier,
  		:@addenda, :@duration, :@average_duration,
  		:@title, :@props, :@startdate,
  		:@enddate, :@sample
  	].each do |v|
  		remove_instance_variable(v) if instance_variables.include?(v)
  	end
  end

	def children
		@children ||= programmes.reject { |p| p.destroyed? or p.rescinded? }.sort
	end
  alias_method :viewable_children, :children

  def <=>(other)
  	b = self.idx <=> other.idx
    b != 0 ? b : self.startdate <=> other.startdate
  end

	def set_saved_at(d)
		if d > self.viewed_at
			self.viewed_at = d
			self.save
			boxset.set_saved_at(d)
		end
	end

	def identifier
		@identifier ||= (self.name || self.number)
	end

  def addenda
    @addenda ||= begin
    	if movie?
    		"#{children.first.date.strftime('%Y')}-#{children.last.date.strftime('%Y')}"
    	else
    		"#{channel.fullname}, #{startdate.strftime('%Y')}, #{programmes.length}x#{average_duration/60}m"
    	end
    end
  end
  alias_method :desc, :addenda

  def spans?(prog)
    prog.channel == self.channel and prog.broadcast_date > startdate.to_date - 15 and prog.broadcast_date <= enddate.to_date + 15
  end

  def duration
	  @duration ||= programmes.collect { |p| p.duration }.inject(:+)
	end

  def average_duration
	  @average_duration ||= begin
	  	d = (duration / programmes.length) + 14
	  	d - d%30
	  end
	end

  def duplicates?(other)
    return false unless children.length == other.children.length
    children.zip(other.children) do |a, b|
      return false unless a.pcrid == b.pcrid
    end
    true
  end

  def hierarchical_title
  	@ht ||= (name || "season #{number}")
  end

  def title
    @title ||= (name || (parent.children.count == 1 ? parent.title : parent.title + " S#{number}"))
  end

	def chid
    channel.namesarray.first
	end

  def acquire(progs)
  	if progs.is_a?(Array)
  		progs = progs.dup
  	else
	  	progs = [progs]
	  end

		oldseasons = []
  	progs.reject { |p| p.season == self }.each do |p|
			oldseasons << p.season unless p.season.nil? or oldseasons.include?(p.season)
			self.programmes << p
      p.season = self
      p.save
		end

		self.save
		self.reset
		oldseasons.each do |s|
			s.reset
			if s.programmes.length == 0
				s.kill!
			else
				s.save
			end
		end
  end

	def startdate
		@startdate ||= (children.count > 0 ? children.first.date : EPOCH)
	end

	def enddate
		@enddate ||= (children.count > 0 ? children.last.date : EPOCH)
	end

	def kill!
		unless destroyed?
			programmes.everyone.kill!
			self.destroy
		end
	end

	def renumber
		programmes.sort.each_with_index do |p, i|
			p.idx = (i+1)*10
			p.save
		end
		@children = nil
	end

end

