defmodule Readability.Regex do
  @moduledoc false
  def regex(:unlikely_candidate),
    do:
      ~r/combx|comment|community|disqus|extra|foot|header|hidden|lightbox|modal|menu|meta|nav|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup/i

  def regex(:ok_maybe_its_a_candidate), do: ~r/and|article|body|column|main|shadow/i

  def regex(:positive), do: ~r/article|body|content|entry|hentry|main|page|pagination|post|text|blog|story/i

  def regex(:negative),
    do:
      ~r/hidden|^hid|combx|comment|com-|contact|foot|footer|footnote|link|masthead|media|meta|outbrain|promo|related|scroll|shoutbox|sidebar|sponsor|shopping|tags|tool|utility|widget/i

  def regex(:div_to_p_elements), do: ~r/<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i

  def regex(:replace_brs), do: ~r/(<br[^>]*>[ \n\r\t]*){2,}/i

  def regex(:replace_fonts), do: ~r/<(\/?)font[^>]*>/i

  def regex(:replace_xml_version), do: ~r/<\?xml.*\?>/i

  def regex(:normalize), do: ~r/\s{2,}/

  def regex(:video), do: ~r/\/\/(www\.)?(dailymotion|youtube|youtube-nocookie|player\.vimeo)\.com/i

  def regex(:protect_attrs), do: ~r/^(?!id|rel|for|summary|title|href|src|alt|srcdoc)/i

  def regex(:img_tag_src), do: ~r/(<img.*src=['"])([^'"]+)(['"][^>]*>)/Ui

  def regex(_key), do: nil
end
