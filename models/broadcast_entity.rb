class BroadcastEntity

  def props
		{
    	'id' => self.id,
    	'type' => self.class.name.downcase.to_sym,
			'title' => title,
      'hierarchical_title' => hierarchical_title,
			'description' => desc,
      'addenda' => addenda,
			'source' => viewable_boxsetter_url,
			'image' => image,
			'channel' => chid,
			'duration' => duration,
			'index' => idx,
			'count' => viewable_children.count,
			'prepared' => true,
			'position' => position,
			'viewed_at' => viewed_at,
			'boxsetprefix' => prefix,
			'movie' => movie?,
			'objects' => [], # viewable_children,
			'filename' => filename,
      'reference' => reference
		}
  end

  def hierarchical_title
    title
  end

  def viewable_boxsetter_url
    @vbu ||= (children.count == 1 ? children.first.viewable_boxsetter_url : boxsetter_url)
  end

  def viewable_children
    @vc ||= children.collect { |c| c.trading_as }
  end

  def trading_as
    @ea ||= (children.count == 1 ? children.first.trading_as : self)
  end

  def filename
    nil
  end

  def reference
    nil
  end

  def number
    parent.children.index(self) + 1
  end

  def prefix
    parent.prefix
  end

  def to_json(x = nil)
    props.to_json(x)
  end

  def image(imtype = :image)
    return DEFAULT_IMAGE if children.length == 0
    @sample ||= children.sample
    @sample.image(imtype)
  end

  def movie?
  	parent.movie?
  end

	class << self

		def orphans
			self.all.reject { |be| !be.parent.nil? }
		end

	end

end
