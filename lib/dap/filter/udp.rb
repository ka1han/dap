module Dap
module Filter

require 'openssl'
require 'net/dns'
require 'bit-struct'

require 'dap/proto/addp'
require 'dap/proto/wdbrpc'
require 'dap/proto/ipmi'

#
# Decode a MDNS Services probe response ( zmap: mdns_5353.pkt )
#
class FilterDecodeMDNSSrvReply
  include BaseDecoder
  def decode(data)
    begin
      r = Net::DNS::Packet.parse(data)
      return if not r

      # XXX: This can throw an exception on bad data
      svcs = r.answer.map {|x| (x.value.to_s) }
      svcs.delete('')
      return if not (svcs and svcs.length > 0)
      return { "mdns_services" => svc.join(" ") }
    rescue ::Exception
    end
    nil
  end
end

#
# Decode a DNS bind.version probe response ( zmap: dns_53.pkt )
#
class FilterDecodeDNSVersionReply
  include BaseDecoder
  def decode(data)
    begin
      r = Net::DNS::Packet.parse(data)
      return if not r

      # XXX: This can throw an exception on bad data
      vers = r.answer.map{|x| x.txt.strip rescue nil }.reject{|x| x.nil? }.first
      return if not vers
      return { "dns_version" => vers }
    rescue ::Exception
      { }
    end
  end
end

#
# Decode a SSDP probe response ( zmap: upnp_1900.pkt )
#
class FilterDecodeUPNP_SSDP_Reply
  include BaseDecoder
  def decode(data)
    head = { }  
    data.split(/\n/).each do |line|
      k,v = line.strip.split(':', 2)
      next if not k
      head["upnp_#{k.downcase}"] = (v.to_s.strip)
    end
    head
  end
end

#
# Decode a VxWorks WDBRPC probe response ( zmap: wdbrpc_17185.pkt )
#
class FilterDecodeWDBRPC_Reply
  include BaseDecoder
  def decode(data)
    info = {}
    head = buff.slice!(0,36)
    info['agent_ver'] = wdbrpc_decode_str(buff)
    info['agent_mtu'] = wdbrpc_decode_int(buff)
    info['agent_mod'] = wdbrpc_decode_int(buff)
    info['rt_type']          = wdbrpc_decode_int(buff)
    info['rt_vers']          = wdbrpc_decode_str(buff)
    info['rt_cpu_type']      = wdbrpc_decode_int(buff)
    info['rt_has_fpp']       = wdbrpc_decode_bool(buff)
    info['rt_has_wp']        = wdbrpc_decode_bool(buff)
    info['rt_page_size']     = wdbrpc_decode_int(buff)
    info['rt_endian']        = wdbrpc_decode_int(buff)
    info['rt_bsp_name']      = wdbrpc_decode_str(buff)
    info['rt_bootline']      = wdbrpc_decode_str(buff)
    info['rt_membase']       = wdbrpc_decode_int(buff)
    info['rt_memsize']       = wdbrpc_decode_int(buff)
    info['rt_region_count']  = wdbrpc_decode_int(buff)
    info['rt_regions']       = wdbrpc_decode_arr(buff, :int)
    info['rt_hostpool_base'] = wdbrpc_decode_int(buff)
    info['rt_hostpool_size'] = wdbrpc_decode_int(buff)
    info
  end
end

#
# Decode a SNMP GET probe response ( zmap: snmp1_161.pkt )
#
class FilterDecodeSNMPGetReply
  include BaseDecoder
  def decode(data)
    asn = OpenSSL::ASN1.decode(data) rescue nil
    return if not asn

    snmp_error = asn.value[0].value rescue nil
    snmp_comm  = asn.value[1].value rescue nil
    snmp_data  = asn.value[2].value[3].value[0] rescue nil
    snmp_oid   = snmp_data.value[0].value rescue nil
    snmp_info  = snmp_data.value[1].value rescue nil

    return if not (snmp_error and snmp_comm and snmp_data and snmp_oid and snmp_info)
    snmp_info = snmp_info.to_s.gsub(/\s+/, ' ').gsub(/[\x00-\x1f]/, ' ')

    return if not snmp_info
    { 'snmp_value' => snmp_info }
  end
end

#
# Decode a IPMI GetChannelAuth probe response ( zmap: ipmi_623.pkt )
#
class FilterDecodeIPMIChanAuthReply
  include BaseDecoder
  def decode(data)
    info = Dap::Proto::IPMI::Channel_Auth_Reply.new(data) 
    return unless info
    {
      'ipmi_version' => (info.ipmi_compat_20) == 1 ? "2.0" : "1.5",
      'ipmi_summary' => info.to_banner
    }
  end
end

#
# Decode a NetBIOS status probe response ( zmap: netbios_137.pkt )
#
class FilterDecodeNetbiosStatusReply
  include BaseDecoder
  def decode(data)
    ret = {}
    head = data.slice!(0,12)

    xid, flags, quests, answers, auths, adds = head.unpack('n6')
    return if quests != 0
    return if answers == 0

    qname = data.slice!(0,34)
    rtype,rclass,rttl,rlen = data.slice!(0,10).unpack('nnNn')
    return if not rlen

    buff = data.slice!(0,rlen)

    names = []

    case rtype
    when 0x21
      hname = nil
      inf = ''
      rcnt = buff.slice!(0,1).unpack("C")[0]
      return unless rcnt
      1.upto(rcnt) do
        tname = buff.slice!(0,15).gsub(/\x00.*/, '').strip
        ttype = buff.slice!(0,1).unpack("C")[0]
        tflag = buff.slice!(0,2).unpack('n')[0]
        names << [ tname, ttype, tflag ]
      end

      maddr = buff.slice!(0,6).unpack("C*").map{|c| "%.2x" % c }.join(":")
      names.each do |name|
        inf << name[0]

        next unless name[1]
        inf << ":%.2x" % name[1]

        next unless name[2]
        if (name[2] & 0x8000 == 0)
          inf << ":U "
        else
          inf << ":G "
        end
      end
    end

    return unless names.length > 0

    { 'netbios_names' => (inf), 'netbios_mac' => maddr, 'netbios_hname' => names[0][0] }
  end
end


end
end