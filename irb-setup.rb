puts 'Loading irb-setup...'

DEFAULT_USER = 'fordn01'
DEFAULT_PASS = "VQ]DP]\u0001W" # need double quotes to allow unicode expansion
{
  'nic' => ['Nic Ford', DEFAULT_USER, DEFAULT_PASS, 0],
  'sam' => ['Sam Ford', DEFAULT_USER, DEFAULT_PASS, 0],
  'simon' => ['Simon Dean', DEFAULT_USER, DEFAULT_PASS, 0]
}.each_pair do |key, data|
  u = User.first_or_create(:name => key)
  u.fullname = data[0]
  u.redux_user = data[1]
  u.default_rp = data[2]
  u.throttle = data[3]
  u.save
end

N = User.first(:name => 'nic')
R = User.first(:name => 'rachel')
B = Boxset.first
S = B.children.first
P = S.children.first

