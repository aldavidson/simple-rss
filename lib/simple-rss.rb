require 'cgi'
require 'time'

class SimpleRSS
  VERSION = "1.2.4"

  attr_reader :items, :source
  alias :entries :items

  @@feed_tags = [
    :id,
    :title, :subtitle, :link,
    :description,
    :author, :webMaster, :managingEditor, :contributor,
    :pubDate, :lastBuildDate, :updated, :'dc:date',
    :generator, :language, :docs, :cloud,
    :ttl, :skipHours, :skipDays,
    :image, :logo, :icon, :rating,
    :rights, :copyright,
    :textInput, :'feedburner:browserFriendly',
    :'itunes:author', :'itunes:category'
  ]

  @@item_tags = [
    :id,
    :title, :link, :'link+alternate', :'link+self', :'link+edit', :'link+replies',
    :author, :contributor,
    :description, :summary, :content, :'content:encoded', :comments,
    :pubDate, :published, :updated, :expirationDate, :modified, :'dc:date',
    :category, :guid,
    :'trackback:ping', :'trackback:about',
    :'dc:creator', :'dc:title', :'dc:subject', :'dc:rights', :'dc:publisher',
    :'feedburner:origLink'
  ]

  def initialize(source, options={})
    @source = source.respond_to?(:read) ? source.read : source.to_s
    @items = Array.new
    @options = Hash.new.update(options)

    parse
  end

  def channel() self end
  alias :feed :channel

  class << self
    def feed_tags
      @@feed_tags
    end
    def feed_tags=(ft)
      @@feed_tags = ft
    end

    def item_tags
      @@item_tags
    end
    def item_tags=(it)
      @@item_tags = it
    end

    # The strict attribute is for compatibility with Ruby's standard RSS parser
    def parse(source, options={})
      new source, options
    end
  end

  private

  def parse
    raise SimpleRSSError, "Poorly formatted feed" unless m = %r{<(channel|feed).*?>.*?</(channel|feed)>}mi.match(@source)

    # Feed's title and link
    feed_content = m[1] if  m = %r{(.*?)<(rss:|atom:)?(item|entry).*?>.*?</(rss:|atom:)?(item|entry)>}mi.match(@source)

    @@feed_tags.each do |tag|
      m = %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi.match(feed_content) ||
          %r{<(rss:|atom:)?#{tag}(.*?)\/\s*>}mi.match(feed_content)  ||
          %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi.match(@source) ||
          %r{<(rss:|atom:)?#{tag}(.*?)\/\s*>}mi.match(@source)

      if m && (m[2] || m[3])
        tag_cleaned = clean_tag(tag)
        instance_variable_set("@#{ tag_cleaned }", clean_content(tag, m[2],m[3]))
        self.class.send(:attr_reader, tag_cleaned)
      end
    end

    # RSS items' title, link, and description
    @source.scan( %r{<(rss:|atom:)?(item|entry)([\s][^>]*)?>(.*?)</(rss:|atom:)?(item|entry)>}mi ) do |match|
      item = Hash.new
      @@item_tags.each do |tag|
        if tag.to_s.include?("+")
          tag_data = tag.to_s.split("+")
          tag = tag_data[0]
          rel = tag_data[1]

          m = %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi.match(match[3]) ||
              %r{<(rss:|atom:)?#{tag}(.*?)rel=['"]#{rel}['"](.*?)/\s*>}mi.match(match[3])
          item[clean_tag("#{tag}+#{rel}")] = clean_content(tag, m[3], m[4]) if m && (m[3] || m[4])
        else
          m = %r{<(rss:|atom:)?#{tag}(.*?)>(.*?)</(rss:|atom:)?#{tag}>}mi.match(match[3]) ||
              %r{<(rss:|atom:)?#{tag}(.*?)/\s*>}mi.match(match[3])
          item[clean_tag(tag)] = clean_content(tag, m[2],m[3]) if m && (m[2] || m[3])
        end
      end

      # Hack to fix blogspot atom feed links pointing to comments issue
      # Looks like the code here is just taking the FIRST link tag and using
      # the href from that. In Blogspot atom feeds, this tends to be the link
      # to the comments - not what we want.
      # The RFC (http://www.ietf.org/rfc/rfc4287.txt) states that
      # 'atom:link elements MAY have a "rel" attribute that indicates the link
      # relation type.  If the "rel" attribute is not present, the link
      # element MUST be interpreted as if the link relation type is
      # "alternate"'
      # Therefore we can work backwards and infer that the 'alternate' link,
      # if present, should be taken as the default.
      if item[:'link+alternate']
        item[:link] = item[:'link+alternate']
      end

      def item.method_missing(name, *args) self[name] end

      @items << item
    end

  end

  def clean_content(tag, attrs, content)
    content = content.to_s
    case tag
      when :pubDate, :lastBuildDate, :published, :updated, :expirationDate, :modified, :'dc:date'
        Time.parse(content) rescue unescape(content)
      when :author, :contributor, :skipHours, :skipDays
        unescape(content.gsub(/<.*?>/,''))
      else
        content.empty? && (m = /href=['"]?([^'"]*)['" ]/mi.match("#{attrs} ") ) ? m[1].strip : unescape(content)
    end
  end

  def clean_tag(tag)
    tag.to_s.gsub(':','_').intern
  end

  def unescape(content)
    if content =~ /([^-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]%)/n then
      CGI.unescape(content).gsub(/(<!\[CDATA\[|\]\]>)/,'').strip
    else
      content.gsub(/(<!\[CDATA\[|\]\]>)/,'').strip
    end
  end
end

class SimpleRSSError < StandardError
end