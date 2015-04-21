require 'nokogiri'
require 'open-uri'

class MtConnect 
  @url
  @base_path
  @name
  @version
  @protocol
  @size 
  @xml 
  

  XML = 0
  GZ  = 1
  TAR = 2

  @references
  @streamsSection
  @devicesSection
  
  @type = nil

  DEBUG_MODE = false

  # List of attributes we will extract / set
  PRODUCT_ATTRIBUTES = [ {'events' => 'events', 'node_ref' => 'instance', 'attribute_ref' => 'instance'},
                         {'samples' => 'samples', 'node_ref' => 'class', 'attribute_ref' => 'product_class'},
                         {'conditions' => 'conditions', 'node_ref' => 'cpetag', 'attribute_ref' => 'cpe_tag'} ]

  MTC_NAMESPACE = {'mtc' => ''}


  attr_accessor :url, :base_path, :name, :version, :state, :protocol, :size, :xml, :references, :diskSection, :networkSection, :virtualSystem


  def initialize 
  end 

  def to_s 
#    (@name + " from " + @url + "\n")
    self.uri 
  end

  def uri 
    if (nil==@protocol) then
      return @url
    else 
      return (@protocol + "://" + @url)
    end
  end

  def initialize(uri)
    if (URI::HTTP==uri.class) then
      uri = uri.to_s 
    end

    (@protocol, @url) = uri.split(":", 2) unless !uri
    @url.sub!(/^\/{0,2}/, '')
    @protocol.downcase
    @url.downcase
    @name = uri.split('/').last
  end 

  def self.create uri
    (@protocol, @url) = uri.split(":", 2) unless !uri
    @url.sub!(/^\/{0,2}/, '')
    @protocol.downcase
    @url.downcase
    if @protocol=='ftp'
      FtpPackage.new(uri)
    elsif @protocol=='http'
      HttpPackage.new(uri)
    elsif @protocol=='https'
      HttpsPackage.new(uri)
    elsif @protocol=='file'
      FilePackage.new(uri)
    elsif @protocol.match(/esx/)
      if @protocol.match(//)
        CustomPackage.new(uri)
      else
        raise NotImplementedError, "Cannot handle this protocol: " + @protocol + "\n"
      end
    elsif @protocol.match(/vc/)
      if @protocol.match(/vc4/)
        Vc4VmPackage.new(uri)
      else
        raise NotImplementedError, "Cannot handle this protocol: " + @protocol + "\n"
      end
    else
      raise NotImplementedError, "Unknown Protocol: " + @protocol + " (bad URI string?)\n"
      VmRepository.new(uri)
    end
  end


  def fetch
  end


  # Caches all of the base elements inside Envelope for fast access
  def loadElementRefs
     children = @xml.root.children

     @references = getChildByName(xml.root, 'References')
     @virtualSystem = getChildByName(xml.root, 'VirtualSystem')

     @diskSection = getChildByName(xml.root, 'DiskSection') || @virtualSystem.add_previous_sibling(xml.create_element('DiskSection', {}))
     @networkSection = getChildByName(xml.root, 'NetworkSection') || @virtualSystem.add_previous_sibling(xml.create_element('NetworkSection', {}))

  end
  
  # Returns the first child node of the passed node whose name matches the passed name.
  def getChildByName(node, childName)
     return node.nil? ? nil : node.children.detect{ |element| element.name == childName}
  end

  # Returns every child node of the passed node whose name matches the passed name.
  def getChildrenByName(node, childName)
     return node.nil? ? [] : node.children.select{ |element| element.name == childName}
  end

  def referenced_file(element) 
    @xml.xpath("//ovf:References/ovf:File[@ovf:id='#{element['fileRef']}']", MTC_NAMESPACE).first
  end
     
  def method_missing(method)
    if DEBUG_MODE
      puts "WARNING: NoSuchMethod Error: " + method.to_s + " ...trying XPath query \n"
    end 
  
    # try with namespace
    data = @xml.xpath("//ovf:" + method.to_s)


    # try without namespace
    if nil===data then
      data = @xml.xpath("//" + method.to_s)
    end

    # try changing method name without namespace
    # i.e. egg_and_ham.classify #=> "EggAndHam"
    if nil==data then
      data = @xml.xpath("//" + method.to_s.classify)
    end

    # try changing method name with namespace
    # i.e. egg_and_ham.classify #=> "EggAndHam"
    if nil==data then
      data = @xml.xpath("//ovf:" + method.to_s.classify)
    end

    return data

  end

  def checkschema(schema)
    response = ""

    isValid = true    
    schema.validate(@xml).each do |error|
      response << error.message + "\n"
      isValid = false
    end

    return [isValid, response]
  end

  def getVmName
    return virtualSystem['id'] || ''
  end

  def getVmDescription
    descNode = getChildByName(virtualSystem, 'Info')
    return descNode.nil? ? '' : descNode.content
  end

  def getVmOS_ID
    osNode = getChildByName(virtualSystem, 'OperatingSystemSection')
    return osNode.nil? ? '' : osNode['id']
  end

  def getVmOS
    os = getVmOS_ID
    return os == '' ? '' : OS_ID_TABLE[os.to_i]
  end 


  # note this is not part of the OVF spec. Specific users could overwrite this method to 
  # store/retrieve patch level in the description field, for example.
  def getVmPatchLevel
  end

  def setVmPatchlevel
  end

  def getVmAttributes
     return {
        'name' => getVmName,
        'description' => getVmDescription,
        'OS' => getVmOS_ID,
        'patch_level' => getVmPatchLevel,
        'CPUs' => getVmCPUs,
        'RAM' => getVmRAM
     }
  end

  def getVmDisks
    disks = Array.new
    filenames = Hash.new
    getChildrenByName(references, 'File').each { |node|
      filenames[node['id']] = node['href']
    }

    getChildrenByName(diskSection, 'Disk').each { |node|
      capacity = node['capacity']
      units = node['capacityAllocationUnits']
      if(units == "byte * 2^40")
         capacity = (capacity.to_i * 1099511627776).to_s
      elsif(units == "byte * 2^30")
         capacity = (capacity.to_i * 1073741824).to_s
      elsif(units == "byte * 2^20")
         capacity = (capacity.to_i * 1048576).to_s
      elsif(units == "byte * 2^10")
         capacity = (capacity.to_i * 1024).to_s
      end
      thin_size = node['populatedSize']
      disks.push({ 'name' => node['diskId'], 'location' => filenames[node['fileRef']], 'size' => capacity, 'thin_size' => (thin_size || "-1") })
    }

    return disks
  end

  def getVmNetworks
    networks = Array.new
    getChildrenByName(networkSection, 'Network').each { |node|
      descriptionNode = getChildByName(node, 'Description')
      text = descriptionNode.nil? ? '' : descriptionNode.text
      networks.push({'location' => node['name'], 'notes' => text })
    }
    return networks
  end

  def getVmReferences
    refs = Array.new
    getChildrenByName(references, 'File').each { |node|
       refs.push({'href' => node['href'], 'id' => node['id'], 'size' => node['size']})
    }
    return refs
  end

  def getVmCPUs
    return getVirtualQuantity(3)
  end

  def getVmRAM
    return getVirtualQuantity(4)
  end

  def getVirtualQuantity(resource)
    getChildrenByName(getChildByName(virtualSystem, 'VirtualHardwareSection'), 'Item').each{ |node|
      resourceType = node.xpath('rasd:ResourceType')[0].text
      resourceType == resource.to_s ? (return node.xpath('rasd:VirtualQuantity')[0].text) : next
    }
  end

  def setVmName(newValue)
    virtualSystem['ovf:id'] = newValue
    nameNode = getChildByName(virtualSystem, 'Name') ||
       getChildByName(virtualSystem, 'Info').add_next_sibling(xml.create_element('Name', {}))
    nameNode.content = newValue
  end

  def setVmDescription(newValue)
    getChildByName(virtualSystem, 'Info').content = newValue
  end

  def setVmOS_ID(newValue)
    getChildByName(virtualSystem, 'OperatingSystemSection')['ovf:id'] = newValue.to_s
  end

  def setVmCPUs(newValue)
    setVirtualQuantity(3, newValue)
  end

  def setVmRAM(newValue)
    setVirtualQuantity(4, newValue)
  end

  def setVirtualQuantity(resource, newValue)
    getChildrenByName(getChildByName(virtualSystem, 'VirtualHardwareSection'), 'Item').each { |node|
      resourceType = node.xpath('rasd:ResourceType')[0].text
      resourceType == resource.to_s ? (node.xpath('rasd:VirtualQuantity')[0].content = newValue) : next
    }
  end

  def removeNetworksFromVirtualHardwareSection
     vhs = getChildByName(virtualSystem, 'VirtualHardwareSection') || virtualSystem.add_child(xml.create_element('VirtualHardwareSection', {}))
     items = getChildrenByName(vhs, 'Item')
     items.each { |item|
        id = getChildByName(item, 'ResourceType')
        if(id.content == '10')
           item.unlink
        end
     }
  end

  def setVmNetworks(networks)
     removeNetworksFromVirtualHardwareSection

     networkNodes = getChildrenByName(networkSection, 'Network')
     vhs = getChildByName(virtualSystem, 'VirtualHardwareSection')

     networkNodes.each { |node|
        updated_network = networks.detect { |network| network.location == node['name'] }
        if(updated_network.nil?)
           node.unlink
        else
           descriptionNode = getChildByName(node, 'Description')
           if((updated_network.notes == '' || updated_network.notes.nil?) && !descriptionNode.nil?)
              descriptionNode.unlink
           elsif(updated_network.notes != '' && !updated_network.notes.nil?)
		descriptionNode = descriptionNode || descriptionNode.add_child(xml.create_element("Description", {}))
              descriptionNode.content = updated_network.notes
           end
        end
     }

     # Find the highest instance ID
     maxID = 0
     items = getChildrenByName(vhs, 'Item')
     items.each { |item|
        itemID = getChildByName(item, 'InstanceID').content.to_i
        if(itemID > maxID)
           maxID = itemID
        end
     }

     rasdNamespace = xml.root.namespace_definitions.detect{ |ns| ns.prefix == 'rasd' }
     netCount = 0

     networks.each { |network|
        if( (networkNodes.detect { |node| network.location == node['name'] }).nil?)
           networkNode = networkSection.add_child(xml.create_element('Network', {'ovf:name' => network.location}))
           if(network.notes != '' && !network.notes.nil?)
              networkNode.add_child(xml.create_element('Description', network.notes))
           end
        end

        maxID += 1
        newNetwork = vhs.add_child(xml.create_element('Item', {}))
        newNetwork.add_child(xml.create_element('AutomaticAllocation', "true")).namespace = rasdNamespace
        newNetwork.add_child(xml.create_element('Connection', network.location)).namespace = rasdNamespace
        newNetwork.add_child(xml.create_element('ElementName', "ethernet" + netCount.to_s)).namespace = rasdNamespace
        newNetwork.add_child(xml.create_element('InstanceID', maxID.to_s)).namespace = rasdNamespace
        newNetwork.add_child(xml.create_element('ResourceSubType', "PCNet32")).namespace = rasdNamespace
        newNetwork.add_child(xml.create_element('ResourceType', "10")).namespace = rasdNamespace
        netCount += 1
     }
  end

  def removeDisksFromVirtualHardwareSection
     vhs = getChildByName(virtualSystem, 'VirtualHardwareSection') || virtualSystem.add_child(xml.create_element('VirtualHardwareSection', {}))
     items = getChildrenByName(vhs, 'Item')
     items.each { |item|
        id = getChildByName(item, 'ResourceType')
        if(id.content == '17')
           item.unlink
        end
     }
  end

  def getOpenChannelOnIDEController(controller, items)
     currentAddress = getChildByName(controller, 'InstanceID').content
     controllerChildren = items.select{ |item| 
        parentNode = getChildByName(item, 'Parent')
        unless(parentNode.nil?)
           parentNode.content == currentAddress
        end
     }
     childAddresses = Array.new
     controllerChildren.each{ |child|
        childAddresses.push(getChildByName(child, 'AddressOnParent').content)
     }
     if(childAddresses.length == 0 || (childAddresses.length == 1 && childAddresses[0] == '1'))
        return '0'
     elsif(childAddresses.length == 1)
        return '1'
     else
        return false
     end
  end

  def buildNewIDEController(vhs, rasdNamespace, newID, newAddress)
     new_controller = vhs.add_child(xml.create_element('Item', {}))
     new_controller.add_child(xml.create_element('Address', newAddress)).namespace = rasdNamespace
     new_controller.add_child(xml.create_element('Description', "IDE Controller " + newAddress)).namespace = rasdNamespace
     new_controller.add_child(xml.create_element('ElementName', "IDEController" + newAddress)).namespace = rasdNamespace
     new_controller.add_child(xml.create_element('InstanceID', newID)).namespace = rasdNamespace
     new_controller.add_child(xml.create_element('ResourceType', "5")).namespace = rasdNamespace
  end

  def getFirstOpenIDEAddress(vhs, rasdNamespace, maxID)
     items = getChildrenByName(vhs, 'Item')
     ide_controllers = items.select{ |item| getChildByName(item, 'ResourceType').content == '5' }

     if(ide_controllers.length == 0)
        buildNewIDEController(vhs, rasdNamespace, maxID, '0')
        return [maxID, '0']

     elsif(ide_controllers.length == 1)
        controller = ide_controllers[0]
        controllerAddress = getChildByName(controller, 'Address').content
        open_address = getOpenChannelOnIDEController(controller, items)
        if(open_address == '0' || open_address == '1')
           return [getChildByName(controller, 'InstanceID').content, open_address]
        elsif(!open_address && controllerAddress == '0')
           buildNewIDEController(vhs, rasdNamespace, maxID, '1')
           return [maxID, '0']
        else
           buildNewIDEController(vhs, rasdNamespace, maxID, '0')
           return [maxID, '0']
        end

     else
        controller = ide_controllers[0]
        controllerAddress = getChildByName(controller, 'Address').content
        open_address = getOpenChannelOnIDEController(controller, items)
        if(open_address == '0' || open_address == '1')
           return [getChildByName(controller, 'InstanceID').content, open_address]
        else
           controller = ide_controllers[1]
           controllerAddress = getChildByName(controller, 'Address').content
           open_address = getOpenChannelOnIDEController(controller, items)
           if(open_address == '0' || open_address == '1')
              return [getChildByName(controller, 'InstanceID').content, open_address]
           else
              return false
           end
        end
     end
  end

  def setVmDisks(disks)
     removeDisksFromVirtualHardwareSection

     fileNodes = getChildrenByName(references, 'File')
     diskNodes = getChildrenByName(diskSection, 'Disk')
     vhs = getChildByName(virtualSystem, 'VirtualHardwareSection')

     icons = Array.new
     getChildrenByName(getChildByName(virtualSystem, 'ProductSection'), 'Icon').each { |node|
        icons.push(node['fileRef'])
     }

     fileNodes.each { |file_node|
        updated_disk = disks.detect { |disk| disk.location == file_node['href'] }
        old_disk_node = diskNodes.detect { |old_node| old_node['id'] == file_node['fileRef'] }

        if(updated_disk.nil?)
           if((icons.detect { |fileRef| fileRef == file_node['id'] }).nil?)
              file_node.unlink
              if(!old_disk_node.nil?)
                 old_disk_node.unlink
              end
           end
        else
           file_node['ovf:id'] = updated_disk.name + '_disk'
           old_disk_node = old_disk_node || diskSection.add_child(xml.create_element('Disk', {}))
           old_disk_node['ovf:fileRef'] = updated_disk.name + '_disk'
           old_disk_node['ovf:capacity'] = updated_disk.size.to_s
           old_disk_node['ovf:diskId'] = updated_disk.name
           old_disk_node['ovf:capacityAllocationUnits'] = "byte * 2^30"
           old_disk_node['ovf:format'] = "http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" 
        end
     }

     # Find the highest instance ID
     maxID = 0
     items = getChildrenByName(vhs, 'Item')
     items.each { |item|
        itemID = getChildByName(item, 'InstanceID').content.to_i
        if(itemID > maxID)
           maxID = itemID
        end
     }

     rasdNamespace = xml.root.namespace_definitions.detect{ |ns| ns.prefix == 'rasd' }

     disks.each { |disk|
        if( (fileNodes.detect { |node| disk.location == node['href'] }).nil?)
           diskSection.add_child(xml.create_element('Disk', {'ovf:capacity' => disk.size.to_s, 'ovf:capacityAllocationUnits' => "byte * 2^30", 'ovf:diskId' => disk.name, 'ovf:fileRef' => disk.name + '_disk', 'ovf:format' => "http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" }))
           references.add_child(xml.create_element('File', {'ovf:href' => disk.location, 'ovf:id' => disk.name + '_disk'}))
        end

        maxID += 1
        address = getFirstOpenIDEAddress(vhs, rasdNamespace, maxID)
        if(!address)
           # PANIC BECAUSE THIS IS BAD MAN, NO AVAILABLE IDE SLOTS
           raise "No IDE slots available"
        else
           maxID += 1
           newDisk = vhs.add_child(xml.create_element('Item', {}))
           newDisk.add_child(xml.create_element('AddressOnParent', address[1])).namespace = rasdNamespace
           newDisk.add_child(xml.create_element('ElementName', disk.name)).namespace = rasdNamespace
           newDisk.add_child(xml.create_element('HostResource', "ovf:/disk/" + disk.name)).namespace = rasdNamespace
           newDisk.add_child(xml.create_element('InstanceID', maxID.to_s)).namespace = rasdNamespace
           newDisk.add_child(xml.create_element('Parent', address[0])).namespace = rasdNamespace
           newDisk.add_child(xml.create_element('ResourceType', "17")).namespace = rasdNamespace
        end
     }

  end

  def setVmAttributes(attributes)
    if attributes['name']
      setVmName(attributes['name'])
    end
    if attributes['description']
      setVmDescription(attributes['description'])
    end
    if attributes['OS']
      setVmOS_ID(attributes['OS'])
    end
    if attributes['patch_level']
      setVmPatchLevel(attributes['patch_level'])
    end
    if attributes['CPUs']
      setVmCPUs(attributes['CPUs'])
    end
    if attributes['RAM']
      setVmRAM(attributes['RAM'])
    end
  end

  def setProductIcon(new_icon, productNode)
     iconNode = getChildByName(productNode, 'Icon')
     if((new_icon == '' || new_icon.nil?) && !iconNode.nil?)
        getChildrenByName(references, 'File').detect { |fileNode| fileNode['id'] == iconNode['fileRef']}.unlink
        iconNode.unlink
     elsif(new_icon != '' && !new_icon.nil?)
        if(iconNode.nil?)
           productNode.add_child(xml.create_element('Icon', {'ovf:fileRef' => productNode['class'] + '_icon'}))
           iconRef = getChildrenByName(references, 'File').detect { |fileNode| fileNode['href'] == new_icon} ||
              references.add_child(xml.create_element('File', {'ovf:href' => new_icon}))
           iconRef['ovf:id'] = productNode['class'] + '_icon'
        else
           productNode.add_child(iconNode)
           getChildrenByName(references, 'File').detect { |fileNode| fileNode['id'] == iconNode['fileRef']}['ovf:href'] = new_icon
        end
     end
  end

   def setPropertyDefault(key, newVal)
      getChildrenByName(virtualSystem, "ProductSection").each{ |product|
         getChildrenByName(product, "Property").each{ |property|
            if(property['key'] == key)
               property['ovf:value'] = newVal
               return
            end
         }
      }
   end

  def setElements(updated_element, parent_node, element_list)
     element_list.each { |element_details|
        updated_value = updated_element[element_details['element_ref']]
        element_node = getChildByName(parent_node, element_details['full_name'])
        #if((updated_value == '' || updated_value.nil?) && !element_node.nil?)
        #   element_node.unlink
        #elsif(updated_value != '' && !updated_value.nil?)
           element_node = element_node.nil? ? parent_node.add_child(xml.create_element(element_details['node_ref'], {})) : parent_node.add_child(element_node)
           element_node.content = updated_value || ''
           if(element_details['required'])
              element_node['ovf:required'] = 'false'
           end
       # end
     }
  end

  def setAttributes(updated_element, parent_node, attribute_list)
     attribute_list.each { |attribute_details|
        updated_value = updated_element[attribute_details['attribute_ref']]
       # (updated_value == '' || updated_value.nil?) ? parent_node.delete(attribute_details['node_ref']) :
        parent_node[attribute_details['full_name']] = updated_value || ''
     }
  end


  # @todo any need to make this a general purpose "writer" ?
  def self.construct_skeleton
     builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.Envelope('xmlns' => 'http://schemas.dmtf.org/ovf/envelope/1', 'xmlns:cim' => "http://schemas.dmtf.org/wbem/wscim/1/common", 'xmlns:ovf' => "http://schemas.dmtf.org/ovf/envelope/1", 'xmlns:rasd' => "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData", 'xmlns:vmw' => "http://www.vmware.com/schema/ovf", 'xmlns:vssd' => "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData", 'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance") {
          xml.References{}
          xml.DiskSection{
             xml.Info "Virtual disk information"
          }
          xml.NetworkSection{
             xml.Info "List of logical networks"
          }
          xml.VirtualSystem('id' => "vm"){
             xml.Info "A virtual machine"
             xml.Name "New Virtual Machine"
             xml.OperatingSystemSection('id' => "94"){
                 xml.Info "The kind of guest operating system"
             }
             xml.VirtualHardwareSection{
                 xml.Info "Virtual hardware requirements"
                 xml.System{
                     xml['vssd'].ElementName "Virtual Hardware Family"
                     xml['vssd'].InstanceID "0"
                     xml['vssd'].VirtualSystemIdentifier "New Virtual Machine"
                 }
                 xml.Item{
                     xml['rasd'].AllocationUnits "herts * 10^6"
                     xml['rasd'].Description "Number of Virtual CPUs"
                     xml['rasd'].ElementName "1 Virtual CPU(s)"
                     xml['rasd'].InstanceID "1"
                     xml['rasd'].ResourceType "3"
                     xml['rasd'].VirtualQuantity "1"
                 }
                 xml.Item{
                     xml['rasd'].AllocationUnits "byte * 2^20"
                     xml['rasd'].Description "Memory Size"
                     xml['rasd'].ElementName "512MB of memory"
                     xml['rasd'].InstanceID "2"
                     xml['rasd'].ResourceType "4"
                     xml['rasd'].VirtualQuantity "512"
                 }
             }
          }
      }

      node = Nokogiri::XML::Comment.new(xml.doc, ' skeleton framework constructed by OVFparse ')
      xml.doc.children[0].add_previous_sibling(node)
    end

    builder.doc.root.children[3].attribute("id").namespace = builder.doc.root.namespace_definitions.detect{ |ns| ns.prefix == "ovf"}
    builder.doc.root.children[3].children[2].attribute("id").namespace = builder.doc.root.namespace_definitions.detect{ |ns| ns.prefix == "ovf"}
      
    newPackage = NewVmPackage.new
    newPackage.xml = builder.doc
    newPackage.loadElementRefs
    return newPackage
  end

   def writeXML(filename)
      file = File.new(filename, "w")
      file.puts(xml.to_s)
      file.close
   end

  # @todo make this a general purpose signing util
  def sign(signature)
    node = Nokogiri::XML::Comment.new(xml, signature)
    xml.children[0].add_next_sibling(node)
  end

  def xpath(string)
    puts @xml.xpath(string)
  end

end 

class HttpVmPackage < VmPackage
  def fetch 
    url = URI.parse(URI.escape(self.uri))
    @xml = Nokogiri::XML(open(url)) do |config|
      config.noblanks.strict.noent
    end

    loadElementRefs
  end
end

class HttpsVmPackage < VmPackage
  def fetch 
    url = URI.parse(URI.escape(self.uri))
    http = Net::HTTP.new(url.host, url.port)
    req = Net::HTTP::Get.new(url.path)
    http.use_ssl = true
    response = http.request(req)
    open(@name, "wb") { |file|
      file.write(response.body)
    }

    @xml = Nokogiri::XML(File.open(@name)) do |config|
#      config.options = Nokogiri::XML::ParseOptions.STRICT | Nokogiri::XML::ParseOptions.NOENT
      config.strict.noent
      config.strict
    end
  
    File.unlink(@name)   
    loadElementRefs
  end


end

class FtpVmPackage < VmPackage
  def fetch 
    url = URI.parse(URI.escape(self.uri))
    ftp = Net::FTP.new(url.host, "anonymous", "ftp-bot@uilabs.org")
      ftp.passive = true
      ftp.getbinaryfile(url.path, @name, 1024)
    ftp.quit()

    @xml = Nokogiri::XML(File.open(@name)) do |config|
      config.strict.noent
      config.strict
    end
  
    File.unlink(@name)   
    loadElementRefs
  end 
end

class FileVmPackage < VmPackage
  def  fetch
    @xml = Nokogiri::XML(File.open(self.url)) do |config|
      config.noblanks.strict.noent
    end
    loadElementRefs
  end
end

class NewVmPackage < VmPackage
  def initialize
  end
end

class Esx4VmPackage < VmPackage
end

class Vc4VmPackage < VmPackage
end

