#! /usr/bin/env ruby

require './common.rb'

User.all.each do |user|
	user.update_boxsets
end
