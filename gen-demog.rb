require 'csv'
require 'securerandom'

def load_existing_voterids(filename)
  voters = {}
  jurisdictions = {}
  cancelled = []
  vtl = open(filename).read

  # <voterTransactionRecord>
  #   <voterid>173491710</voterid>
  #   <date>2014-07-11T14:59:41.147</date>
  #   <action>cancelVoterRecord</action>
  #   <form>VoterRecordUpdate</form>
  #   <jurisdiction>CHESAPEAKE CITY</jurisdiction>
  #   <leo>General Registrar CHESAPEAKE CITY</leo>
  #   <notes>cancelOther</notes>
  # </voterTransactionRecord>

  i = 0
  re = /<voterTransactionRecord>.*?<voterid>(\d+)<\/voterid>.*?<action>(.+?)<\/action>.*?<jurisdiction>(.+?)<\/jurisdiction>.*?<\/voterTransactionRecord>/m
  vtl.scan(re) do |voter_id, action, jurisdiction|
    i += 1
    voters[voter_id] = jurisdiction

    voters_in_jurisdiction = jurisdictions[jurisdiction] || []
    voters_in_jurisdiction << voter_id
    jurisdictions[jurisdiction] = voters_in_jurisdiction.uniq

    cancelled << voter_id if action =~ /cancel/i
  end

  return voters, jurisdictions, cancelled
end

def load_jurisdictions(filename)
  first = true
  jurisdictions = {}

  CSV.foreach(filename) do |row|
    if first
      first = false
      next
    end

    full_locality = row[0]

    # Locality: 001 ACCOMACK COUNTY
    if full_locality =~ /^Locality: (\d{3}) (.*)$/
      locality_code = $1
      locality_name = $2
      total_active_voters = row[10].gsub(',', '').to_i

      jurisdictions[locality_code] = {
        name: locality_name,
        total_active_voters: total_active_voters
      }
    end
  end

  jurisdictions
end

def render_demog_for_locality(locality_code, locality_name, active_voters, existing_voters, voters_in_jurisdiction, cancelled)
  voters_in_jurisdiction ||= []

  # render existing first
  voters_in_jurisdiction.each do |full_ref|
    render_vdr(full_ref, locality_name, cancelled)
    active_voters -= 1
  end

  # auto-generate what's left
  ref = 0
  while active_voters > 0
    full_ref = "#{locality_code}#{ref.to_s.rjust(6, '0')}"
    ref += 1
    next unless existing_voters[full_ref].nil?

    render_vdr(full_ref, locality_name, cancelled)
    active_voters -= 1
  end
end

def render_vdr(full_ref, locality_name, cancelled)
  reg_year   = rand(67) + 1930
  reg_month  = rand(12) + 1
  reg_date   = rand(28) + 1
  reg_date   = "#{reg_year}-#{reg_month.to_s.rjust(2, '0')}-#{reg_date.to_s.rjust(2, '0')}"
  birth_year = reg_year - 18
  reg_status = cancelled.include?(full_ref) ? "Cancelled" : full_ref =~ /99$/ ? "Inactive" : "Active"
  gender     = full_ref =~ /9999$/ ? "Unknown" : full_ref.to_i % 2 == 0 ? "Female" : "Male"
  race       = full_ref =~ /[0-6]$/ ? "White" : full_ref =~ /[78]$/ ? "Black" : full_ref =~ /[0-5]9$/ ? "Asian" : "Other"
  party_code = full_ref.to_i % 100
  party      = party_code < 47 ? "Democratic" : party_code < 86 ? "Republican" : "Other"

  overseas                  = bool(full_ref =~ /9.$/)
  military                  = bool(full_ref =~ /9[0-8]$/)
  prot                      = bool(full_ref =~ /000$/)
  disabled                  = bool(full_ref =~ /001$/)
  absentee_ongoing          = bool(full_ref =~ /9.$/)
  absentee_in_this_election = bool(full_ref =~ /8[0-5]$/)

  puts <<-END
  <voterDemographicRecord>
    <voterid>#{full_ref}</voterid>
    <jurisdiction>#{locality_name}</jurisdiction>
    <regDate>#{reg_date}</regDate>
    <yearOfBirth>#{birth_year}</yearOfBirth>
    <regStatus>#{reg_status}</regStatus>
    <gender>#{gender}</gender>
    <race>#{race}</race>
    <politicalPartyName>#{party}</politicalPartyName>
    <overseas>#{overseas}</overseas>
    <military>#{military}</military>
    <protected>#{prot}</protected>
    <disabled>#{disabled}</disabled>
    <absenteeOngoing>#{absentee_ongoing}</absenteeOngoing>
    <absenteeInThisElection>#{absentee_in_this_election}</absenteeInThisElection>
    <precinctSplitID></precinctSplitID>
    <zip>0000</zip>
  </voterDemographicRecord>
END
end

def render_demog_header
  puts <<-END
<?xml version="1.0" encoding="utf-8"?>
<voterDemographicExtract xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <header>
    <origin>Sample Virginia Data</origin>
    <originUniq>#{SecureRandom.uuid}</originUniq>
    <hashAlg>SHA1</hashAlg>
    <createDate>#{Time.now.strftime('%Y-%m-%dT%H:%M:%S')}</createDate>
  </header>
END
end

def render_demog_footer
  puts <<-END
</voterDemographicExtract>
END
end

def bool(v)
  v ? "true" : "false"
end


existing_voters, voters_in_jurisdictions, cancelled = load_existing_voterids('vtl_va_1.01.xml')

if ARGV[0] == '-targeted'
  render_demog_header
  voters_in_jurisdictions.each do |jur, voter_ids|
    voter_ids.each do |voter_id|
      render_vdr(voter_id, jur, cancelled)
    end
  end
  render_demog_footer
else
  jurisdictions   = load_jurisdictions('count-by-locality.csv')

  render_demog_header
  jurisdictions.each do |code, data|
    render_demog_for_locality(code, data[:name], data[:total_active_voters], existing_voters, voters_in_jurisdictions[data[:name]], cancelled)
  end
  render_demog_footer
end
