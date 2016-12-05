class Channel
  include DataMapper::Resource

  property :id,           Serial
  property :fullname,     String,  :default => ''
  property :idx,          Integer, :default => 0
  property :last_checked, DateTime
  property :channeltype,	Integer, :default => 0

  has n, :seasons
  has n, :programmes
  has n, :users, :through => Resource

	TYPE_BBC = 0x01
	TYPE_ITV = 0x02
	TYPE_CH4 = 0x04
	TYPE_CH5 = 0x08
	TYPE_EXT = 0x10
  TYPE_OTH = TYPE_CH4|TYPE_CH5|TYPE_EXT
	TYPE_ALL = TYPE_BBC|TYPE_ITV|TYPE_OTH

  def <=>(other)
    self.idx <=> other.idx
  end

  def name
    @name ||= fullname.downcase.gsub(/[^a-z0-9]/,'')
  end

	def namesarray
		@namesarray ||= begin
      if channeltype == TYPE_BBC
        [name, name+'hd']
      else
        [name]
      end
    end
	end

  class << self

    def allnames
	 	   @allnames ||= all.collect { |c| c.namesarray }.flatten
  	end

  end

end

