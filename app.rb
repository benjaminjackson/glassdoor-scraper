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

  # Date
  row << DateTime.parse(review.at_css('time.date').andand.text)

  # Summary
  row << review.at_css('.summary').text.andand.strip

  # Title
  row << review.at_css('.rating [title]')["title"].to_f

  current_past_and_title = review.at_css('.authorJobTitle').andand.text.andand.strip

  # Current or past employee
  if current_past_and_title.split(" - ").length
    current_past = current_past_and_title.split(" - ").andand.first
    row << current_past.andand.include?("Current")
  else
    # Glassdoor doesn’t force employees to specify current/past
    row << "Unspecified"
  end

  # Title
  row << current_past_and_title.split(" - ").last

  # Location
  row << review.at_css('.authorLocation').andand.text.andand.strip

  # NPS
  row << review.css('.reviewBodyCell.recommends span').andand.first.andand.text.andand.strip

  # Outlook
  row << review.css('.reviewBodyCell.recommends span').andand[1].andand.text.andand.strip

  # CEO Approval
  row << review.css('.reviewBodyCell.recommends span').andand[2].andand.text.andand.strip

  employment_status_and_tenure = review.at_css('.mainText').andand.text.andand.strip

  # Employment Status
  full_time = employment_status_and_tenure.match(/[a-z]+\-time/).andand[0].andand.include?("full")
  row << full_time

  # Tenure
  if employment_status_and_tenure.include?(" for ")
    row << employment_status_and_tenure.sub(/I (?:worked|have been working) at .+ for /, '').capitalize
  else
    # Not all reviews provide this
    row << "Unspecified"
  end

  # Pros/Cons
  review.css('.v2__EIReviewDetailsV2__fullWidth')[0..1].each do |review_detail|
    review_text = review_detail.andand.css('p').andand.map(&:text).andand.join("\n")
    review_text_cleaned = review_text.
      andand.sub(/^(Pros|Cons)/, '').
      # remove numbers from ordered lists
      andand.gsub(/^[0-9]{1,2}\.\s?/, "").
      # remove dashes from unordered lists
      andand.gsub(/^\s?(\-|\•|\*)\s?/, "").
      andand.gsub(/\n/, "\n\n").
      andand.strip
    row << review_text_cleaned
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
