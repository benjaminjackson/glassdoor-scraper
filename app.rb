require 'csv'
require 'nokogiri'
require 'andand'
require 'google_drive'

APPLESCRIPT = <<EOF
tell application "Safari"
  do JavaScript "document.documentElement.outerHTML" in document 1
end tell
EOF

SPREADSHEET_KEY = ENV['GLASSDOOR_SCRAPER_SPREADSHEET_KEY']
COMPANY_NAME = ARGV[0]

STDERR.puts "Pulling HTML..."

outer_html = `osascript -e '#{APPLESCRIPT}'`

STDERR.puts "Extracting..."

unless SPREADSHEET_KEY.to_s.empty?
  session = GoogleDrive::Session.from_config("config.json")
  ws = session.spreadsheet_by_key(SPREADSHEET_KEY).worksheets[0]
end

doc = Nokogiri::HTML.fragment(outer_html)

doc.css('.empReview').each do |review|  
  row = []

  next if review.at_css('.featuredFlag')

  row[0] = review.at_css('time.date').andand.text.andand.strip
  row[1] = review.at_css('.summary').text.andand.strip
  row[2] = review.at_css('.rating .value-title')["title"].to_i
  row[3] = review.at_css('.authorJobTitle').andand.text.andand.strip
  row[4] = review.at_css('.authorLocation').andand.text.andand.strip
  row[5] = review.css('.reviewBodyCell.recommends span').andand.first.andand.text.andand.strip
  row[6] = review.css('.reviewBodyCell.recommends span').andand[1].andand.text.andand.strip
  row[7] = review.css('.reviewBodyCell.recommends span').andand[2].andand.text.andand.strip
  row[8] = review.at_css('.mainText').andand.text.andand.strip
  review.css('.v2__EIReviewDetailsV2__fullWidth')[0..1].each do |review_detail|
    row << review_detail.andand.css('p').andand.map(&:text).andand.join("\n")
  end

  unless SPREADSHEET_KEY.to_s.empty?
    next_row = ws.num_rows + 1
    row.each_with_index do |item, index|
      ws[next_row, index + 1] = row[index]
    end
  else
    STDOUT.puts(row.to_csv)
  end
end

unless SPREADSHEET_KEY.to_s.empty?
  ws.save
end
