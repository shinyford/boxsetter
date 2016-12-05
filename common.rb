require 'rubygems'
require 'dm-core'
require 'dm-validations'
require 'dm-migrations'
require 'net/http'
require 'json'
require 'time'
require 'cgi'

class Everyone
	def initialize(o)
		@obj = o
	end
	def method_missing(name, *args)
		if @obj.is_a?(Array)
			@obj.collect { |x| x.send(name, *args) }
		elsif @obj.is_a?(Hash)
			a = {}
			@obj.each_pair { |k,v| a[k] = v.send(name, *args) }
			a
		else
			@obj.send(name, *args)
		end
	end
end

class DateTime
	def to_millis
		(self.to_time.to_f * 1000).to_i
	end
end

class Object
  def everyone
		@everyone ||= Everyone.new(self)
  end

  def methods_uniq
  	self.methods.reject { |m| Object.methods.include?(m) }.sort
  end
end

class Hash
  def to_json(x=nil)
    '{' + self.keys.collect { |k| k.to_json(x) + ':' + self[k].to_json(x) }.join(',') + '}'
  end
end

class Array
  def to_json(x=nil)
    '[' + self.collect { |k| k.to_json(x) }.join(',') + ']'
  end
  def find_by_index(idx)
    self.reject { |o| o.idx != idx }
  end
  def select_collect
    collect { |a| yield(a) }.compact
  end
end

class String
	def repword(k, v)
    self.split(' ').collect { |a| a == k ? v : a }.join(' ')
	end
	def sanitise
		self.strip.gsub('\'', '').gsub(/[^a-zA-Z0-9\(\) ]/, '-').gsub('-', ' - ').gsub('  ', ' ')
	end
  def to_searchterm
    self.strip.downcase.gsub(/[^a-z0-9'\:\&\+\. ]/,'')
  end
  def to_json(x = nil)
    return '"' + self + '.json"' if self.match(/boxsetter\.gomes\.com\.es\/[^\.]*$/)
    super(x)
  end
  def blank?
  	self == ''
  end
  def escape
  	URI.escape(self)
  end
  def to_crid
		if self.match(/^(crid:\/\/)?fp\.bbc\.co\.uk\/([0-9A-Z]+)$/)
      $2
		elsif self.match(/^(crid:\/\/)?bds\.tv\/([0-9A-Z]+)$/)
      $2
		elsif self.match(/^(crid:\/\/)?www\.itv\.com\/([0-9#]+)$/)
      $2.gsub('#','-')
	  elsif self.match(/^(crid:\/\/)?www\.channel4\.com\/([0-9]+)\/([0-9]+)$/)
	  	$2 + '-' + $3
		elsif self.match(/^(crid:\/\/)?www\.five\.tv\/([A-Z0-9#]+)$/)
      $2.gsub('#','-') + '$V'
	  else
	    self.delete("^a-zA-Z0-9")
	  end
  end
  def hexEncode
    self.each_byte.map { |b| sprintf('%02x', b) }.join
  end
  def hexDecode
    self.scan(/../).map { |x| x.hex }.pack('c*')
  end
  def titleise
  	@@commoners ||= ['and', 'a', 'an', 'the', 'of', 'on', 'in', 'with']
  	res = []
  	self.downcase.split(/\s+/).each_with_index do |a, i|
  		res << (i == 0 || !@@commoners.include?(a) ? a.capitalize : a)
  	end
  	res.join(' ')
  end
end

def nil.blank?
	true
end

REDUX_HOST = 'devapi.bbcredux.com'
REDUX_SCHEME = 'http'
REDUX_URL = REDUX_SCHEME + '://' + REDUX_HOST
REDUX_URLS = 'https://' + REDUX_HOST

BXSTR_HOST = 'boxsetter.gomes.com.es'
BXSTR_SCHEME = 'https'
BXSTR_URL = BXSTR_SCHEME + '://' + BXSTR_HOST

DEFAULT_IMAGE = 'default.png'

EPOCH = DateTime.new(1965, 11, 30)

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db_boxsetter.sqlite3")
require './models/broadcast_entity'
require './models/user'
require './models/channel'
require './models/boxset'
require './models/season'
require './models/programme'
DataMapper.auto_upgrade!

[
  ['BBC One', Channel::TYPE_BBC],
  ['BBC Two', Channel::TYPE_BBC],
  ['BBC Three', Channel::TYPE_BBC],
  ['BBC Four', Channel::TYPE_BBC],
  ['CBBC', Channel::TYPE_BBC],
  ['CBeebies', Channel::TYPE_BBC],
  ['ITV1', Channel::TYPE_ITV],
  ['ITV2', Channel::TYPE_ITV],
  ['ITV3', Channel::TYPE_ITV],
  ['ITV4', Channel::TYPE_ITV],
  ['Channel 4', Channel::TYPE_CH4],
  ['More4', Channel::TYPE_CH4],
  ['E4', Channel::TYPE_CH4],
  ['Five', Channel::TYPE_CH5],
  ['Dave', Channel::TYPE_EXT],
  ['S4C', Channel::TYPE_EXT]
].each_with_index do |data, index|
  fullname, channeltype = data
  c = Channel.first_or_create(:fullname => fullname)
	c.channeltype = channeltype
  c.idx = index
	c.save
end
