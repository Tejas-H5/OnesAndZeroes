//---------A logic gate simulator----------
//By Tejas Hegde
//To add:
//-Load/save circuits
//-Composite circuits --first priority
//-----------------------------------------

final int TEXTSIZE = 12;

//Putting these here cause you cant make static vars in processing
//This is to prevent multiple things being dragged at once
UIElement draggedElement = null; 
boolean mouseOver = false;
//A rectangular UI element that all classes will derive from 
class UIElement{
  protected UIElement parent;
  public float x,y,w=5,h=5;
  private boolean clicked = false;
  protected int dragThreshold = 2;
  protected boolean acceptUIInput = true;
  
  public void MoveTo(float x1, float y1){
    x = x1; y = y1;
  }
  
  public float WorldX(){
    if(parent!=null)
      return parent.WorldX()+x;
      
    return x;
  }
  
  public float WorldY(){
    if(parent!=null)
      return parent.WorldY()+y;
      
    return y;
  }
  
  public void UIRespond(){
    if(!acceptUIInput)
      return;
    
    float x1 = WorldX()-w/2;
    float y1 = WorldY()-h/2; 
    //handle mouse clicks in an override if we aren't clicking an in/output
    if(mouseInside(x1,y1,w,h)){
      OnHover();
      mouseOver = true;
      if(mousePressed){
        if(!clicked){
          OnMousePress();
          clicked=true;
        } else {
          if(!(draggedElement==this))
            OnMouseDown();
        }
        
        if(abs(mouseX-pmouseX)+abs(mouseY-pmouseY)>dragThreshold){
            if(draggedElement==null){
              draggedElement = this;
              OnDragStart();
            }
        }
      } else if(clicked) {
        clicked = false;
        OnMouseRelease();
        draggedElement = null;
      }
    } else {
      if(clicked){
        clicked = false;
        if(!mousePressed){
          OnMouseRelease();
        }
      }
      
      if(draggedElement==this){
        if(!mousePressed)
          draggedElement = null;
      }
    }
    
    if(draggedElement==this){
      OnDrag();
    }
  }
  
  //this function is called every frame, and can also be used to start events
  public void Draw(){    
    float x1 = WorldX()-w/2;
    float y1 = WorldY()-h/2; 
    
    UIRespond();
    //let the input overrides determine the colour of this rectangle
    rect(x1,y1,w,h);
  }
  
  public void OnMousePress(){}
  
  public void OnMouseRelease(){}
  
  public void OnMouseDown(){}

  public void OnHover(){}
  
  public void OnDrag(){}
  
  public void OnDragStart(){}
}

class Pin extends UIElement{
  protected LogicGate chip;
  
  public boolean IsDeleted(){
    return chip.deleted;
  }
  
  Pin(LogicGate parentChip){
    chip = parentChip;
    parent = parentChip;
    dragThreshold = -1;
  }
  
  @Override
  public void OnHover(){
    stroke(foregroundCol);
    rect(WorldX()-w/2+2,WorldY()-w/2+2,w-4,h-4);
    if(!mousePressed){
      lastSelectedPin = this;
    }
  }
  
  @Override
  public void Draw(){
    stroke(foregroundCol);
    if(IsConnected()){
      fill(Value() ? trueCol : falseCol);
    } else {
      noFill();
    }
    super.Draw();
  }
  
  public void UpdatePin(){
    if(Value()!=lastValue){
      OnValueChange();
    }
    lastValue = Value();
  }
  
  boolean lastValue = false;
  public boolean Value(){return false;}
  public boolean IsConnected(){return true;}
  
  public void OnValueChange(){
    chip.UpdateLogic();
  }
}

//An input pin on a logic gate. Every input can link to at most 1 output pin
class InPin extends Pin{
  private OutPin input;
  
  public InPin(LogicGate p){
    super(p);
  }
  
  public void Connect(OutPin in){
    input = in;
    OnValueChange();
  }

  @Override
  public void OnHover(){
    super.OnHover();
  }
  
  @Override
  public void Draw(){
    super.Draw();
    if(IsConnected()){
      line(WorldX(),WorldY(),input.WorldX(),input.WorldY());
    }
  }
  
  @Override
  public boolean IsConnected(){
    return (input!=null);
  }
  
  @Override
  void UpdatePin(){
    super.UpdatePin();
    if(IsConnected()){
      if(input.IsDeleted()){
        //We need to remove all references to the deleted chip in order for the garbage collecter to collect it
        Connect(null);
      }
    }
  }

  @Override
  public boolean Value(){
    if(input!=null){
      return input.Value();
    } else {
      return false;
    }
  }
  
  @Override
  public void OnDragStart(){
    ClearPinSelection();
    Connect(null);
  }
  
  @Override
  public void OnDrag(){
    if(mouseButton==LEFT){
      lastSelectedInput = this;
      stroke(gateHoverCol);
      line(WorldX(), WorldY(), MouseXPos(), MouseYPos());
    }
  }
  
  @Override
  public void OnMouseRelease(){
    if(mouseButton==LEFT){
      MakeConnection(lastSelectedOutput, this);
    }
  }
}

//This is a pin that outputs a value to an input pin.
class OutPin extends Pin{    
  OutPin(LogicGate p){
    super(p);
  }
  
  public void SetValue(boolean v){
    if(IsDeleted())
      return;
      
    value = v;
  }
  
  @Override
  public boolean Value(){
    return value;
  }

  @Override
  public void OnHover(){
    super.OnHover();
    if(!mousePressed){
      lastSelectedOutput = this;
    }
  }

  @Override
  public void Draw(){
    fill(Value() ? trueCol : falseCol);
    super.Draw();
  }
  
  @Override
  public void OnDragStart(){
    ClearPinSelection();
  }
  
  @Override
  public void OnDrag(){
    if(mouseButton==LEFT){
      lastSelectedOutput = this;
      stroke(gateHoverCol);
      line(WorldX(), WorldY(), MouseXPos(), MouseYPos());
    }
  }
  
  @Override
  public void OnMouseRelease(){
    if(mouseButton==LEFT){
      MakeConnection(this, lastSelectedInput);
    }
  }
  
  boolean value = false;
}

//a different number for each logic gate
//does not need to be saved for each gate
long logicGateID = 0;
LogicGate gateUnderMouse = null;

//The base class for all logic gates. contains most of the functionality
abstract class LogicGate extends UIElement implements Comparable<LogicGate>{
  String title = "uninitializedGate";
  public boolean deleted = false;
  protected boolean showText = true;
  boolean drawPins = true;
  protected int level = 0;
  InPin[] inputs;
  
  //This will be set by any function traversing a list of logicgates
  public int arrayIndex;
  
  void ArrangeInputs(){
    if(inputs==null)
      return;
    
    for(int i = 0; i < inputs.length; i++){
      inputs[i].x = -w/2-inputs[i].w/2;
      inputs[i].y = -h/2.0 + h*((float)(i+1)/((float)inputs.length+1));
    }
  }
  
  OutPin[] outputs;
  void ArrangeOutputs(){
    if(outputs==null)
      return;
    for(int i = 0; i < outputs.length; i++){
      outputs[i].x = w/2+outputs[i].w/2;
      outputs[i].y = -h/2.0 + h*((float)(i+1)/((float)outputs.length+1));
    }
  }
  
  int compareTo(LogicGate lg){
    return Integer.compare(level,lg.level);
  }
    
  public int NumGates(){
    return 1;
  }
  
  public int NumGates(String type){
    if(title==type)
      return 1;
    return 0;
  }
  
  public int OutputIndex(OutPin output){
    for(int i = 0; i < outputs.length; i++){
      if(outputs[i]==output){
        return i;
      }
    }
    return -1;
  }
  
  public void Decouple(){
    deleted = true;
    if(inputs!=null){
      for(InPin p : inputs){
        p.Connect(null);
      }
    }
  }
  
  public abstract LogicGate CopySelf();
  public abstract int PartID();
  
  public String PartIDString(){
    return nf(PartID(),0,0);
  }
  
  public String GetParts(){
    //looks like: (partID,x,y,0110100010)
    //will have to change for other parts
    String s = "("+PartIDString() + "," + str(x) + "," + str(y)+","; 
    s+="O";//so we know when the outputs are coming
    if(outputs!=null){
      for(int i = 0; i < outputs.length;i++){
        s+= outputs[i].Value() ? "1" : "0";
      }
    }
    s+=")";
    return s;
  }
  
  //only works if the array it's supposed to be a part of has been indexed properly
  public String GetInputs(){
    //will look like: <thisGate>[gateindex,outputIndex][null][null], <anotherGate>[so on so forth]
    String s = "<"+arrayIndex+">";
    for(int i = 0; i < inputs.length; i++){
      s+="[";
      if(inputs[i].IsConnected()){
        OutPin out = inputs[i].input;
        //the indexing thing only works if the chip of the incoming output is in the same array/group
        if(out.parent.parent==parent){
          s+= out.chip.arrayIndex;
          s+=",";
          s+= out.chip.OutputIndex(out);
        }
      }
      
      s+="]";
    }
    return s;
  }
  
  //won't work if the gates are of different kinds
  public void CopyValues(LogicGate other){
    x = other.x;
    y = other.y;
    parent = other.parent;
    for(int i = 0; i < inputs.length; i++){
      inputs[i].Connect(other.inputs[i].input);
    }
    
    if(outputs!=null){
      for(int i = 0; i < outputs.length; i++){
        outputs[i].SetValue(other.outputs[i].Value());
      }
    }
  }
  
  @Override 
  public void OnDragStart(){
    if(!selection.contains(this)){
      ClearGateSelection();
    }
  }
  
  @Override
  public void OnDrag(){
    if(mouseButton==LEFT){
      //drag functionality
      if(dragStarted)
        return;
        
      float dX = ToWorldX(mouseX)-ToWorldX(pmouseX);
      float dY = ToWorldY(mouseY)-ToWorldY(pmouseY);
      dragStarted = true;
      if(selection.size()==0){
        x+= dX;
        y+= dY;
      } else {
        for(int i = 0; i < selection.size(); i++){
          selection.get(i).x += dX;
          selection.get(i).y += dY;
        }
      }
    }
  }
  
  @Override
  public void OnHover(){
    fill(gateHoverCol);
    gateUnderMouse = this;
  }
  
  @Override
  public void Draw(){
    if(outputs!=null){
      if(outputs.length>0){
        fill(outputs[0].Value() ? trueCol : falseCol);
      }
    }
    stroke(foregroundCol);
    super.Draw();
    if(showText){
      textAlign(CENTER);
      fill(foregroundCol);
      text(title,WorldX(),WorldY()+TEXTSIZE/4.0);
    }
    
    stroke(foregroundCol);
    
    if(drawPins){
      if(inputs!=null){
        for(int i = 0; i < inputs.length; i++){
          inputs[i].Draw();
        }
      }
      
      if(outputs!=null){
        for(int i = 0; i < outputs.length; i++){
          outputs[i].Draw();
        }
      }
    }
  }
  
  //will involve setting outputs in overrides, which should cause a cascading change
  protected void UpdateLogic(){}
  
  public void UpdateIOPins(){
    if(inputs!=null){
      for(InPin in : inputs){
        in.UpdatePin();
      }
    }
    
    if(outputs!=null){
      for(OutPin out : outputs){
        out.UpdatePin();
      }
    }
  }
}

//should not be instantiated
abstract class BinaryGate extends LogicGate{
  public BinaryGate(){
    super();
    w = 50; 
    h = 30;    
    
    inputs = new InPin[2];
    inputs[0] = new InPin(this);
    inputs[1] = new InPin(this);
    /*
    inputs[0] = new InPin(this);
    inputs[0].MoveTo(-w/2-inputs[0].w/2,inputs[0].h);
    inputs[1] = new InPin(this);
    inputs[1].MoveTo(-w/2-inputs[1].w/2,-inputs[1].h);
    */
    ArrangeInputs();
    
    outputs = new OutPin[1];
    outputs[0] = new OutPin(this);
    ArrangeOutputs();
  }
}

class AndGate extends BinaryGate{
  public AndGate(){
    super();
    title = "&";
  }
  
  @Override
  protected void UpdateLogic(){
    outputs[0].SetValue(inputs[0].Value() && inputs[1].Value());
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new AndGate();
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return ANDGATE;
  }
}

class OrGate extends BinaryGate{
  public OrGate(){
    super();
    title = "|";
  }
  
  @Override
  protected void UpdateLogic(){
    outputs[0].SetValue(inputs[0].Value() || inputs[1].Value());
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new OrGate();
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return ORGATE;
  }
}

class NotGate extends LogicGate{
  public NotGate(){
    super();
    w=20;
    h=20;
    inputs = new InPin[1];
    inputs[0] = new InPin(this);
    inputs[0].MoveTo(-w/2-inputs[0].w/2,0);
    
    title = "!";
    outputs = new OutPin[1];
    outputs[0] = new OutPin(this);
    outputs[0].MoveTo(w/2+outputs[0].w/2,0);
  }
  
  @Override
  protected void UpdateLogic(){
    outputs[0].SetValue(!inputs[0].Value());
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new NotGate();
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return NOTGATE;
  }
}

class NandGate extends BinaryGate{
  public NandGate(){
    super();
    title = "!&";
  }
  
  @Override
  protected void UpdateLogic(){
    outputs[0].SetValue(!(inputs[0].Value() && inputs[1].Value()));
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new NandGate();
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return NANDGATE;
  }
}

class Ticker extends LogicGate{
  public Ticker(){
    super();
    title = "ticc";
    showText = false;
    inputs = new InPin[16];
    w = 50;
    h = 50;
    for(int i = 0; i < inputs.length; i++){
      inputs[i]=new InPin(this);
      inputs[i].w = w/16.0;
      inputs[i].h = inputs[i].w;
      inputs[i].MoveTo(-w/2-inputs[i].w/2, -h/2 + inputs[0].h/2 + i * inputs[i].h); 
    }
    
    outputs = new OutPin[1];
    outputs[0] = new OutPin(this);
    ArrangeOutputs();
  }
  
  int phase = 0;
  int ticks = 0;
  @Override
  public void UpdateIOPins(){
    super.UpdateIOPins();
    phase ++;
    if(phase > ticks){
      outputs[0].SetValue(true);
      phase = 0;
    } else {
      outputs[0].SetValue(false);
    }
  }
  
  @Override
  public void Draw(){
    super.Draw();
    fill(foregroundCol);
    textAlign(CENTER);
    text("t: "+phase,WorldX(),WorldY()-6);
    text("tn: "+ticks,WorldX(),WorldY()+6);
  }
  
  @Override
  protected void UpdateLogic(){
    ticks = 0;
    for(int i = 0; i < inputs.length; i++){
      if(inputs[i].Value()){
        ticks += pow(2,i);
      }
    }
  }
  
  @Override
  public LogicGate CopySelf(){
    Ticker lg = new Ticker();
    lg.CopyValues(this);
    lg.ticks = ticks;
    lg.phase = phase;
    return lg;
  }
  
  @Override
  public int PartID(){
    return TICKGATE;
  }
}

class RelayGate extends LogicGate{
  public RelayGate(){
    super();
    w=15;
    h=15;
    inputs = new InPin[1];
    inputs[0] = new InPin(this);
    inputs[0].MoveTo(-w/2-inputs[0].w/2,0);
    
    title = ">";
    outputs = new OutPin[1];
    outputs[0] = new OutPin(this);
    outputs[0].MoveTo(w/2+outputs[0].w/2,0);
  }
  
  @Override
  void OnMouseRelease(){
    super.OnMouseRelease();
    if((mouseButton==LEFT)&&(draggedElement!=this)){
      outputs[0].SetValue(!outputs[0].Value());
    }
  }  
  
  @Override
  protected void UpdateLogic(){
    if(inputs[0].IsConnected()){
      outputs[0].SetValue(inputs[0].Value());
    }
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new RelayGate();
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return INPUTGATE;
  }
}

class LCDGate extends LogicGate{
  public LCDGate(float wid,float hei){
    super();
    showText=false;
    w=wid; h=hei;
    title = "LC";
    inputs = new InPin[1];
    inputs[0] = new InPin(this);
    inputs[0].MoveTo(-w/2-inputs[0].w/2,0);
  }
  
  @Override
  public void Draw(){
    super.Draw();
    stroke(foregroundCol);
    fill(inputs[0].Value() ? foregroundCol : backgroundCol);
    rect(WorldX()-w/2,WorldY()-h/2,w,h);
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new LCDGate(w,h);
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return LCDGATE;
  }
}

class Base10Gate extends LogicGate{
  public Base10Gate(float fontSize){
    super();
    showText=false;
    h = fontSize;
    textSize(h);
    w = textWidth("2,147,483,647")+20;
    textSize(TEXTSIZE);
    title = "Num";
    inputs = new InPin[32];
    for(int i = 0; i < 32; i++){
      inputs[i]=new InPin(this);
      inputs[i].w = w/32.0;
      inputs[i].h = inputs[i].w;
      inputs[i].MoveTo(-w/2 + i * inputs[i].w + inputs[0].w/2,h/2+inputs[i].h/2); 
    }
  }
  String number = "0";
  
  @Override
  public void Draw(){
    noFill();
    super.Draw();
    stroke(foregroundCol);
    textAlign(CENTER);
    textSize(h);
    fill(0,225,0);
    text(number,WorldX(),WorldY()+h/4);
    textSize(TEXTSIZE);
  }
  
  @Override
  void UpdateLogic(){
    int num = 0;
    for(int i = 0; i < inputs.length; i++){
      if(inputs[i].Value()){
        num = num | (1<<i);
      }
    }
    number = nf(num,0,0);
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new Base10Gate(h);
    lg.CopyValues(this);
    return lg;
  }
  
  @Override
  public int PartID(){
    return BASE10GATE;
  }
}

class PixelGate extends LogicGate{
  public PixelGate(float wid, float hei){
    super();
    w=wid; h = hei;
    showText=false;
    title = "PX";
    inputs = new InPin[24];
    for(int i = 0; i < 8; i++){
      inputs[i] = new InPin(this);
      inputs[i].w = hei/8.0;
      inputs[i].h = inputs[i].w;
      inputs[i].MoveTo(-w/2.0-inputs[i].w/2.0, h/2.0 - (i)*inputs[i].h - inputs[i].h/2.0);
    }
    for(int i = 8; i < 16; i++){
      inputs[i] = new InPin(this);
      inputs[i].w = hei/8.0;
      inputs[i].h = inputs[i].w;
      inputs[i].MoveTo(w/2.0+inputs[i].w/2.0, h/2.0 - (i-8)*inputs[i].h - inputs[i].h/2.0);
    }
    for(int i = 16; i < 24; i++){
      inputs[i] = new InPin(this);
      inputs[i].w = hei/8.0;
      inputs[i].h = inputs[i].w;
      inputs[i].MoveTo(-w/2.0+inputs[i].w/2.0 + (i-16)*inputs[i].w, h/2.0 + inputs[i].h/2.0);
    }
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new PixelGate(w,h);
    lg.CopyValues(this);
    return lg;
  }
  
  public void Draw(){
    super.Draw();
    int r = 0,g=0,b=0;
    for(int i = 0; i < 8; i++){
      if(inputs[i].Value()){
        r += pow(2,i);
      }
      
      if(inputs[i+8].Value()){
        g += pow(2,i);
      }
      
      if(inputs[i+16].Value()){
        b += pow(2,i);
      }
    }
    
    stroke(foregroundCol);
    fill(r,g,b);
    rect(WorldX()-w/2,WorldY()-h/2,w,h);
    fill(foregroundCol);
    
    textAlign(CENTER);
    textSize(inputs[0].h/2);
    for(int i = 0; i < 8; i ++){
      text((int)pow(2,i), inputs[i].WorldX(),inputs[i].WorldY());
      text((int)pow(2,i), inputs[i+8].WorldX(),inputs[i+8].WorldY());
      text((int)pow(2,i), inputs[i+16].WorldX(),inputs[i+16].WorldY());
    }
    textSize(TEXTSIZE);
  }
  
  @Override
  public int PartID(){
    return PIXELGATE;
  }
}

boolean contains(LogicGate[] arr, LogicGate lg){
  for(LogicGate l : arr){
    if(l==lg)
      return true;
  }
  return false;
}

//Makes sure that the copied gates aren't connected to the old ones
LogicGate[] CopyPreservingConnections(LogicGate[] gates){
  LogicGate[] newGates = new LogicGate[gates.length];
  
  for(int i = 0; i < gates.length; i++){
    newGates[i] = gates[i].CopySelf();
    if(gates[i].inputs!=null){
      //we need to know what their array positions are in order to do the next part
      gates[i].arrayIndex = i;
    }
  }
  
  //make the connections copied -> copied instead of original -> copied
  for(int i = 0; i < gates.length; i++){
    for(int j = 0; j < gates[i].inputs.length; j++){
      //get the output gate from our gates 
      if(!gates[i].inputs[j].IsConnected())
        continue;
        
      LogicGate outputLg = gates[i].inputs[j].input.chip;
      InPin copiedInput = newGates[i].inputs[j];
      //Only carry over connections if they are within the array/group
      if(contains(gates,outputLg)){
        int gateIndex = outputLg.arrayIndex;        
        int outputIndex = outputLg.OutputIndex(gates[i].inputs[j].input);
        OutPin copiedOutput = newGates[gateIndex].outputs[outputIndex];
        copiedInput.Connect(copiedOutput);
      } else {
        copiedInput.Connect(null);
      }
    }
  }
  
  return newGates;
}


String filepath(String filename){
  return "Saved Circuits\\"+filename+".txt";
}



void LoadProject(String filePath){
  Cleanup();
  ClearGateSelection();
  ClearPinSelection();
  String[] file = loadStrings(filePath);
  if(file.length < 2){
    println("not my type of file tbh");
    return; 
  }
  String data = file[1];
  LogicGate[] loadedGates;
  try{
    loadedGates = RecursiveLoad(data);
  } catch(Exception e){
    println("Something went wrong: " + e.getMessage());
    return;
  }
  
  for(LogicGate lg : loadedGates){
    circuit.add(lg);
    selection.add(lg);
  }
}

//tf is this hackerrank? this is definately one of those questions you would find there lmao
int findCorrespondingBracket(String data, int start, int end, char openBrace, char closeBrace){
  int sum = 0;
  for(int i = start; i < end; i++){
    if(data.charAt(i)==openBrace){
      sum++;
    } else if(data.charAt(i)==closeBrace){
      sum--;
    }
    if(sum==0)
      return i;
  }
  return -1;
}

//Load all the parts in a string into an array
LogicGate[] RecursiveLoad(String data){
  int partsIndex = data.lastIndexOf('|');
  int start = data.indexOf('{');
  int end = data.indexOf(',',start+1);
  int n = int(data.substring(start+1,end));
  LogicGate[] loaded = new LogicGate[n];
  //start is at {   end is at ,
  for(int i =  0; i < n; i++){
    start = data.indexOf('(',end);
    if(data.charAt(start+1)=='{'){
      //Find the end of this part and recursive load the {} bit and then it's metadata with LoadGroup
      end = findCorrespondingBracket(data,start,data.length(), '(', ')');
      loaded[i] = LoadGroup(data,start,end);
    } else {
      end = data.indexOf(')',start+1);
      //Normal load it since it's just a primitive
      loaded[i] = LoadPart(data,start,end);
    }
  }
  
  //Connect all the parts we just loaded
  start = partsIndex;
  for(int i =  0; i < n; i++){
    start = data.indexOf('<',start)+1;
    end = data.indexOf('>',start);
    int gateIndex = int(data.substring(start,end));
    int start2 = start;
    int end2 = start;
    for(int j = 0; j < loaded[gateIndex].inputs.length;j++){
      start2 = data.indexOf('[',start2)+1;
      end2 = data.indexOf(']',start2);
      
      //Continue if no connections
      if(data.charAt(start2)==']'){
        continue;
      }
      
      //else make the connections
      int div = data.indexOf(',',start2);
      int outputGateIndex = int(data.substring(start2,div));
      int outputIndex = int(data.substring(div+1,end2));
      loaded[gateIndex].inputs[j].Connect(loaded[outputGateIndex].outputs[outputIndex]);
    }
  }
  
  return loaded;
}

//assigns a part's outputs. not to be called on it's own
void assignOutputs(LogicGate lg, String outputs){
  if(lg.outputs==null)
    return;
  for(int i = 0; i < outputs.length(); i++){
    lg.outputs[i].SetValue((outputs.charAt(i)=='1'));
  }
}

//assigns a group it's x,y,w,h values and inputs. start is the index of the start of the first value, and end is the ). not to be called on it's own
void loadMetadata(LogicGate lg, String data, int start, int end){
  int a = start;
  int b = data.indexOf(',',a+1);
  lg.x = float(data.substring(a,b));
  a = b+1;
  b = data.indexOf(',',a);
  lg.y = float(data.substring(a,b));

  a=b+1;
  if(data.charAt(a)=='O'){
    assignOutputs(lg,data.substring(a+1,end));
    return;
  }
  //otherwise we have to load in the width and height and then do so
  b = data.indexOf(',',a);
  lg.w = float(data.substring(a,b));
  a = b+1;
  b = data.indexOf(',',a);
  lg.h = float(data.substring(a,b));
  assignOutputs(lg,data.substring(a+1,end));
}

//loads a primitive part from a string.
//where start is the ( and end is the )
LogicGate LoadPart(String data, int start, int end){
  int a = start+1;
  int b = data.indexOf(',',a);
  LogicGate lg = CreateGate(int(data.substring(a,b)));
  a = b+1;
  loadMetadata(lg,data,a, end);
  return lg;
}

//Loads a group. start is the opening (, and end is the ). Groups can have more groups. The base case would be a regular LoadPart
LogicGate LoadGroup(String data, int start, int end){
  int partEnd = findCorrespondingBracket(data,start+1,end,'{','}')+1; 
  //Connections are resolved in here
  LogicGate[] gates = RecursiveLoad(data.substring(start+1,partEnd));
  LogicGate lg = new LogicGateGroup(gates);
  start = partEnd + 1;
  loadMetadata(lg,data,start,end);
  return lg;
}

void SaveProject(String filePath){
  String[] s = {CircuitString(circuit)};
  saveStrings(filePath,s);
}

String CircuitString(ArrayList<LogicGate> cir){
  String s = "OnesAndZeroes Savefile. Don't modify these next lines if you want things to work proper\r\n";
  s+=GateString(cir.toArray(new LogicGate[cir.size()]));
  return s;
}

String GateString(LogicGate[] gates){
  //looks like: {(part1),(part2),..,(partn)|<part>[otherPart,outputFromOtherOart],<soOn>[AndSoForth]}
  String s = "{";
  s+=gates.length+",";
  //get all of the parts, and index the gates
  for(int i = 0; i < gates.length; i++){
    s+=gates[i].GetParts();
    gates[i].arrayIndex = i;
  }
  s+="|";
  for(int i = 0; i < gates.length; i++){
    s+=gates[i].GetInputs();
  }
  s+="}";
  return s;
}

class LogicGateGroup extends LogicGate{
  LogicGate[] gates;
  boolean expose = true;
  int numGates;
  @Override
  int NumGates(){
    int sum = 0;
    for(LogicGate lg : gates){
      sum += lg.NumGates();
    }
    return sum;
  }
  
  //creates a group using an array of existing gates (they can also be groups themselves :0)
  //exposes all unlinked inputs and outputs
  LogicGateGroup(LogicGate[] gateArray){
    gates = gateArray;
    title = "LG";
    showText = false;
    
    //find the bounding box for the group
    //also find the abstraction level
    //also find exposed input pins
    
    float minX=gates[0].x;
    float maxX=gates[0].x;
    float minY=gates[0].y; 
    float maxY=gates[0].y;
    
    int maxAbstraction = 0; 
    ArrayList<InPin> temp = new ArrayList<InPin>();
    ArrayList<OutPin> usedOutputs = new ArrayList<OutPin>();
    for(LogicGate lg : gates){
      lg.drawPins = true;
      lg.acceptUIInput = false;
      
      minX=min(lg.x-lg.w/2-5, minX);
      maxX = max(lg.x+lg.w/2+5, maxX);
      minY=min(lg.y-lg.h/2-5,minY);
      maxY=max(lg.y+lg.h/2+5,maxY);
      lg.parent = this;
      maxAbstraction = max(lg.level, maxAbstraction);
      numGates += lg.NumGates();
      
      //expose inputs
      for(InPin p : lg.inputs){
        if(!p.IsConnected()){
          temp.add(p);
          p.parent = this;
        } else {
          //we need to check if it is connected to an output from the outside the group
          LogicGate lg2 = p.input.chip;
          boolean found = false;
          for(LogicGate lg3 : gates){
            if(lg2==lg3){
              found = true;
              break;
            }
          }
          
          if(!found){
            temp.add(p);
            p.parent = this;
          } else {
            usedOutputs.add(p.input);
          }
        }
      }
    }
    
    x = (minX+maxX)/2.0;
    y = (minY+maxY)/2.0;
    w = maxX-minX;
    h = maxY-minY;
    inputs = temp.toArray(new InPin[temp.size()]);
    
    //make the x and y positions of the gates relative to this
    //and also find all the unlinked outputs
    ArrayList<OutPin> unusedOutputs = new ArrayList<OutPin>();
    for(LogicGate lg : gates){
      lg.x -= x;
      lg.y -= y;
      if(lg.outputs!=null){
        for(OutPin p : lg.outputs){
          if(!usedOutputs.contains(p)){
            unusedOutputs.add(p);
            p.parent = this;
          }
        }
      }
    }
    outputs = unusedOutputs.toArray(new OutPin[unusedOutputs.size()]);
    
    ArrangeInputs();
    ArrangeOutputs();
    level = maxAbstraction+1;
  }
  
  @Override
  public void Draw(){
    noFill();
    super.Draw();
    
    if(expose){
      for(LogicGate lg : gates){
        lg.Draw();
      }
    }
  }
  
  @Override
  public void Decouple(){
    super.Decouple();
    for(LogicGate lg : gates){
      lg.Decouple();
    }
  }
  
  @Override
  public void UpdateIOPins(){
    for(LogicGate lg : gates){
      lg.UpdateIOPins();
    }
  }
  
  @Override
  public LogicGate CopySelf(){
    LogicGate lg = new LogicGateGroup(CopyPreservingConnections(gates));
    lg.CopyValues(this);
    return lg;
  }
  
  @Override int PartID(){
    return -1;
  }
  
  //Save every gate recursively lmao
  @Override
  public String PartIDString(){
    return GateString(gates);
  }
}

//----------------- CUSTOM UI ELEMENTS ----------------
//used by other ui elements
class CallbackFunctionInt {
  public void f(int i){}
}

class StringMenu extends UIElement{
  ArrayList<String> elements;
  float elementHeight = 11;
  float padding = 2;
  String heading;
  CallbackFunctionInt f;
  
  public StringMenu(String[] arr, String title, CallbackFunctionInt intFunction){
    heading = title;
    elements = new ArrayList<String>();
    for(String s : arr){
      elements.add(s);
    }
    f = intFunction;
    
    //setup the dimensions
    int max = heading.length();
    for(Object s : elements){
      if(s.toString().length() > max){
        max = s.toString().length();
      }
    }
    
    w = max * 7 + 20 + 2 * padding;
    h = (elements.size()+1) * (elementHeight+padding) + padding;
    x = w/2;
    y = h/2;
  }
  
  @Override
  public void MoveTo(float x1, float y1){
    x = x1+w/2; y = y1+h/2;
  }
  
  @Override
  public void OnMouseRelease(){
    listClicked = false;
  }
  
  public void AddEntry(String s){
    elements.add(s);
  }
  
  boolean listClicked = false;
  
  @Override
  public void Draw(){
    noFill();
    stroke(foregroundCol);
    super.Draw();
    fill(menuHeadingCol);
    textAlign(CENTER);
    text(heading,WorldX(),WorldY()-h/2+elementHeight);
    for(int i = 0; i < elements.size();i++){
      noFill();
      float x1 = WorldX()-w/2+padding;
      float y1 = WorldY()+padding + i*(elementHeight+padding)-h/2+elementHeight;
      float w1 = w-2*padding;
      float h1 = elementHeight;
      if(mouseInside(x1,y1,w1,h1)){
        mouseOver = true;
        fill(gateHoverCol);
        if(mousePressed && (mouseButton==LEFT)){
          noFill();
          if(!listClicked){
            listClicked = true;
            f.f(i);
          }
        }
      }
      rect(x1,y1, w1, h1);
    }
    
    fill(foregroundCol);
    textAlign(CENTER);
    for(int i = 0; i < elements.size();i++){
      float x1 = WorldX();
      float y1 = WorldY()+ (i+1)*(elementHeight+padding)-h/2+elementHeight-padding;      
      text(elements.get(i),x1,y1);
    }
  }
}

//will be used to input names and stuff
class TextInput extends UIElement{
  boolean isTyping = false;
  boolean startedTyping = false;
  boolean persistent = false;
  int align;
  char lastKey = 'r';
  float x0,y0,w0,h0;
  public void Show(float x1, float y1, float h1,int aline){
    isTyping = true;
    x=x1;y=y1;h=h1; align = aline;
    x0=x;y0=y;h0=h;w0=w;
  }
  
  protected String text = "";
  protected String edited = "";
  
  String Text(){
    return text;
  }
  
  private boolean isLegit(char c){
    return (((c>='a')&&(c<='z'))||((c>='A')&&(c<='Z')))&&("(){}[]/.,;'\" \\=!@#$%^&*~`".indexOf(c)==-1);
  }
  
  private void drawContents(String str){
    updateDimensions(str);
    stroke(foregroundCol);
    strokeWeight(1/scale);
    noFill();
    super.Draw();
    strokeWeight(1);
    fill(foregroundCol);
    textAlign(CENTER);
    text(str,WorldX(),WorldY()+h/4.0);
    //carat
    if(isTyping){
      line(WorldX()+w/2-5, WorldY()+h/1.5,WorldX()+w/2-5, WorldY()-h/1.5);
    }
  }
  
  protected void updateDimensions(String str){
    float newW = max(100,textWidth(str)+10);
    if(align==LEFT){
      x += (newW - w)/2.0;
    } else if(align==RIGHT){
      x -= (newW - w)/2.0;
    }
    w = newW;
  }
  
  protected boolean isLegit(String s){
    if(s.length()==0){
      return false;
    }
    
    return true;
  }
  
  @Override
  public void Draw(){
    textSize(h);
    if(isTyping){
      if(!startedTyping){
        startedTyping = true;
        edited = "";
      }
      drawContents(edited);
      if(keyPushed){
        keyPushed = false;
        if(keyThatWasPushed=='\n'){
          isTyping = false;
          if(isLegit(edited)){
            text = edited;
          }
        } else if(keyThatWasPushed=='\b'){
          if(edited.length()>0){
            edited = edited.substring(0,edited.length()-1);
          }
        } else if(isLegit(keyThatWasPushed)) {
          edited += keyThatWasPushed;
        }
      }
    } else {
      if(persistent){
        drawContents(text);
      }
      startedTyping = false;
    }
    textSize(TEXTSIZE);
  }
}

class TextLabel extends TextInput{
  String label;
  boolean clicked1 = false;
  TextLabel(String l, String text1, float x, float y, float h,int aline){
    text = text1;
    Show(x,y,h,aline);
    isTyping = false;
    label = l;
    persistent = true;
    align = aline;
  }
  
  @Override
  void OnMousePress(){
    if(mouseButton==LEFT){
      isTyping = true;
    }
  }
  
  @Override
  void Draw(){
    super.Draw();
    textSize(h);
    textAlign(align);
    text(label, WorldX()-w/2,WorldY()+h/4);
    textSize(TEXTSIZE);
    if(!clicked1){
      if(mousePressed){
        if(!mouseInside(WorldX()-w/2,WorldY()-h/2,w,h)){
          isTyping = false;
        }
      }
    }
  }
}

//INPUT SYSTEM copy pasted from another personal project
boolean[] keyJustPressed = new boolean[23];
boolean[] keyStates = new boolean[23];
boolean keyDown(int Key) { return keyStates[Key]; }
boolean keyPushed(int Key){
  if(!keyDown(Key))
    return false;
    
  if(!keyJustPressed[Key]){
    keyJustPressed[Key] = true;
    return true;
  }
  return false;
}

final int AKey = 0;
final int DKey = 1;
final int WKey = 2;
final int SKey = 3;
final int CKey = 4;
final int QKey = 5;
final int EKey = 6;
final int ShiftKey = 7;
final int CtrlKey = 8;
final int PKey = 9;
final int RKey = 10;
final int BKey = 11;
final int ZKey = 12;
final int XKey = 13;
final int VKey = 14;
final int SpaceKey = 15;
final int FKey = 16;
final int NKey = 17;
final int TabKey = 18;
final int FSlashKey = 19;
final int TKey = 20;
final int GKey = 21;
final int LKey = 22;

boolean shiftChanged = false;
//maps the processing keys to integers in our key state array, so we can add new keys as we please
HashMap<Character, Integer> keyMappings = new HashMap<Character, Integer>();

boolean keyPushed = false;
char keyThatWasPushed; 
int keyCodeThatWasPushed;
void keyPressed(){
  keyPushed = true;
  keyThatWasPushed = key;
  keyCodeThatWasPushed = keyCode;
  
  if(keyMappings.containsKey(key)){
    keyStates[keyMappings.get(key)]=true;
  }
  
  if(keyCode==SHIFT){
    if(!keyStates[ShiftKey]){
      keyStates[ShiftKey] = true;
      shiftChanged = true;
    }
  }
  
  if(keyCode==CONTROL){
    keyStates[CtrlKey] = true;
  }
  
  if(keyCode==TAB){
    keyStates[TabKey] = true;
  }
}

void keyReleased(){  
  if(keyMappings.containsKey(key)){    
    keyStates[keyMappings.get(key)]=false;
    keyJustPressed[keyMappings.get(key)]=false;
  }
  
  if(keyCode==SHIFT){
    if(keyStates[ShiftKey]){
      keyStates[ShiftKey]=false;
      shiftChanged = true;
    }
    keyJustPressed[ShiftKey]=false;
  }
  
  if(keyCode==CONTROL){
    keyStates[CtrlKey]=false;
    keyJustPressed[CtrlKey]=false;
  }
  
  if(keyCode==TAB){
    keyStates[TabKey] = false;
    keyJustPressed[TabKey]=false;
  }
  
  dragStartPos = -1;
  dragDelta = 0;
}

float dragStartPos = 0;
float dragDelta = 0;

void setup(){
  size(800,600);
  
  //textFont(createFont("Monospaced",TEXTSIZE));
  circuit = new ArrayList<LogicGate>();
  circuitGroups = new ArrayList<LogicGateGroup>();
  deletionQueue = new ArrayList<LogicGate>();
  selection = new ArrayList<LogicGate>();
  AddGate(0);
  
  //setup the input system
  keyMappings.put('a', AKey);
  keyMappings.put('A', AKey);
  keyMappings.put('s', SKey);
  keyMappings.put('S', SKey);
  keyMappings.put('d', DKey);
  keyMappings.put('D', DKey);
  keyMappings.put('w', WKey);
  keyMappings.put('W', WKey);
  keyMappings.put('q', QKey);
  keyMappings.put('Q', QKey);
  keyMappings.put('e', EKey);
  keyMappings.put('E', EKey);
  keyMappings.put('c', CKey);
  keyMappings.put('C', CKey);
  keyMappings.put('p', PKey);
  keyMappings.put('P', PKey);
  keyMappings.put('r', RKey);
  keyMappings.put('R', RKey);
  keyMappings.put('b', BKey);
  keyMappings.put('B', BKey);
  keyMappings.put('z', ZKey);
  keyMappings.put('Z', ZKey);
  keyMappings.put('x', XKey);
  keyMappings.put('X', XKey);
  keyMappings.put('v', VKey);
  keyMappings.put('V', VKey);
  keyMappings.put('f', FKey);
  keyMappings.put('F', FKey);
  keyMappings.put('n', NKey);
  keyMappings.put('N', NKey);
  keyMappings.put('/', FSlashKey);
  keyMappings.put('?', FSlashKey);
  keyMappings.put('t', TKey);
  keyMappings.put('T', TKey);
  keyMappings.put(' ', SpaceKey);
  keyMappings.put('g',GKey);
  keyMappings.put('G',GKey);
  keyMappings.put('l',LKey);
  keyMappings.put('L',LKey);
  
  menus = new ArrayList<UIElement>();
  UIElement logicGateAddMenu = new StringMenu(gateNames, "ADD GATE", new CallbackFunctionInt(){
    @Override
    public void f(int i){
      AddGate(i);
    }
  });
  
  menus.add(logicGateAddMenu);
  
  UIElement outputGateAddMenu = new StringMenu(outputNames, "ADD OUTPUT GATE", new CallbackFunctionInt(){
    @Override
    public void f(int i){
      AddGate(i+gateNames.length);
    }
  });
  outputGateAddMenu.MoveTo(logicGateAddMenu.w+10,0);
  menus.add(outputGateAddMenu);
  
  UIElement logicGateGroupAddMenu = new StringMenu(new String[]{}, "ADD A GROUP", new CallbackFunctionInt(){
    @Override
    public void f(int i){
      AddGateGroup(i);
    }
  });
  
  logicGateGroupAddMenu.MoveTo(outputGateAddMenu.WorldX()+outputGateAddMenu.w/2f+10,0);
  menus.add(logicGateGroupAddMenu);
  
  fileNameField = new TextLabel("Circuit name: ","unnamed",-20,-50,20,RIGHT);
  menus.add(fileNameField);
}


ArrayList<UIElement> menus;

//moving the screen around
float xPos=0;
float yPos=0;
float scale=1;

color backgroundCol = color(255);
color foregroundCol = color(0);
color trueCol = color(0,255,0,100);
color falseCol = color(255,0,0,100);
color gateHoverCol = color(0,0,255,100);
color menuHeadingCol = color(0,0,255);
color warningCol = color(255,0,0);

float ToWorldX(float screenX){
  return ((screenX-width/2)/scale)+xPos;
}

float MouseXPos(){
  return ToWorldX(mouseX);
}

float ToWorldY(float screenY){
  return ((screenY-height/2)/scale)+yPos;
}

float MouseYPos(){
  return ToWorldY(mouseY);
}

//Have some helper functions here
boolean pointInside(float mX, float mY,float x, float y, float w, float h){
  if(mX>x){
    if(mX < x+w){
      if(mY > y){
        if(mY < y + h){
          return true;
        }
      }
    }
  }
  
  return false;
}

boolean mouseInside(float x, float y, float w, float h){
  return pointInside(ToWorldX(mouseX), ToWorldY(mouseY), x, y,w,h);
}

ArrayList<LogicGate> circuit;
ArrayList<LogicGateGroup> circuitGroups;
//related to the dragging of buttons
boolean dragStarted = false;

//deletes the given gate, else deletes everything that's selected
void DeleteGates(LogicGate lg){
  if(selection.size()==0){
    deletionQueue.add(lg);
    lg.Decouple();
  } else {
    for(LogicGate selectedGate : selection){
      deletionQueue.add(selectedGate);
      selectedGate.Decouple();
    }
  }
}

void DeleteGates(LogicGate[] lg){
  for(LogicGate g : lg){
    deletionQueue.add(g);
    g.Decouple();
  }
}

ArrayList<LogicGate> deletionQueue;

void Cleanup(){
  if(deletionQueue.size()>0){
    for(LogicGate lg : deletionQueue){
      circuit.remove(lg);
      lg.Decouple();
    }
    deletionQueue.clear();
    
    ClearGateSelection();
    ClearPinSelection();
  }
}

//creates a new group from the selected elements
void CreateNewGroup(){
  if(numSelected <= 1)
    return;
  if(selection.size()<=1)
    return;
    
  LogicGate[] gates = selection.toArray(new LogicGate[selection.size()]);
  LogicGateGroup g = new LogicGateGroup(gates);
  circuit.add(g);
  for(LogicGate lg: gates){
    circuit.remove(lg);
  }
  
  ClearGateSelection();
}

//Copies the selection
void Duplicate(){
  if(selection.size()==0)
    return;
    
  LogicGate[] newGates = CopyPreservingConnections(selection.toArray(new LogicGate[selection.size()]));
  selection.clear();
  float xMax=newGates[0].x,yMax=newGates[0].y;
  float xMin=newGates[0].x,yMin=newGates[0].y;
  for(LogicGate lg : newGates){
    xMax = max(xMax,lg.x);
    xMin = min(xMin,lg.x);
    yMax = max(yMax,lg.y);
    yMin = min(yMin,lg.y);
  }
  
  for(LogicGate lg : newGates){
    lg.x += xMax-xMin;
    lg.y -= yMax-yMin;
    selection.add(lg);
    circuit.add(lg);      
  }
}

//soon my brodas, soon
void AddGateGroup(int i){
  
}

String outputNames[] = {"LCD Pixel", "24-bit Pixel", "LCD Pixel large", "LCD 24-bit Pixel large","Int32 readout"};
String gateNames[] = {"input / relay point","And", "Or", "Not", "Nand","Ticker"};
final int INPUTGATE = 0;
final int ANDGATE = 1;
final int ORGATE = 2;
final int NOTGATE = 3;
final int NANDGATE = 4;
final int TICKGATE = 5;
final int LCDGATE = TICKGATE + 1;
final int PIXELGATE = TICKGATE + 2;
final int LLCDGATE = TICKGATE + 3;
final int LPIXELGATE = TICKGATE + 4;
final int BASE10GATE = TICKGATE + 5;

LogicGate CreateGate(int g){
  LogicGate lg;
  switch(g){
    case(INPUTGATE): {
      lg = new RelayGate();
      break;
    }
    case(ANDGATE):{
      lg = new AndGate();
      break;
    }
    case(ORGATE):{
      lg = new OrGate();
      break;
    }
    case(NOTGATE):{
      lg = new NotGate();
      break;
    }
    case(NANDGATE):{
      lg = new NandGate();
      break;
    }
    case(TICKGATE):{
      lg = new Ticker();
      break;
    }
    case(LCDGATE):{
      lg = new LCDGate(20,20);
      break;
    }
    case(PIXELGATE):{
      lg = new PixelGate(20,20);
      break;
    }
    case(LLCDGATE):{
      lg = new LCDGate(80,80);
      break;
    }
    case(LPIXELGATE):{
      lg = new PixelGate(80,80);
      break;
    }
    case (BASE10GATE):{
      lg = new Base10Gate(30);
      break;
    }
    default:{
      lg = new RelayGate();
      break;
    }
  }
  return lg;
}

//This function can add every primitive gate
void AddGate(int g){
  LogicGate lg = CreateGate(g);
  lg.x=cursor.WorldX();
  lg.y=cursor.WorldY();
  circuit.add(lg);
}

Pin lastSelectedPin;
OutPin lastSelectedOutput = null;
InPin lastSelectedInput = null;
ArrayList<OutPin> selectedOutputs = new ArrayList<OutPin>();
ArrayList<InPin> selectedInputs = new ArrayList<InPin>();
void ConnectSelected(){
  int n = min(selectedInputs.size(),selectedOutputs.size());
  if(n==0){
    for(InPin p : selectedInputs){
      p.Connect(null);
    }
  }
  if(selectedOutputs.size()>0){
    for(int i = 0; i < selectedInputs.size(); i++){
      MakeConnection(selectedOutputs.get(i%selectedOutputs.size()),selectedInputs.get(i));
    }
  } else {
    for(int i = 0; i < selectedInputs.size(); i++){
      MakeConnection(null,selectedInputs.get(i));
    }
  }
}

void ClearPinSelection(){
  lastSelectedPin = null;
  lastSelectedOutput = null;
  lastSelectedInput = null;
  selectedOutputs.clear();
  selectedInputs.clear();
}

void ClearGateSelection(){
  selection.clear();
  numSelected = 0;
}

void MakeConnection(OutPin from, InPin to){
  if(from==null)
    return;
  if(to==null)
    return;
  to.Connect(from);
}

ArrayList<LogicGate> selection;
int numSelected = 0;
//2D cursor. will be used to make selections
class Cursor2D extends UIElement{
  float xBounds = 0;
  float yBounds = 0;
  boolean cursorPlaced = false;
  
  @Override
  public void Draw(){
    w=20.0/scale;
    h=w;
    stroke(foregroundCol);
    noFill();
    ellipse(WorldX(),WorldY(),w,w);
    drawCrosshair(WorldX(),WorldY(),w);
    UIRespond();
  }
  
  @Override
  public void OnDragStart(){
    Reset();
  }
  
  @Override
  public void OnDrag(){
    float dX = ToWorldX(mouseX)-ToWorldX(pmouseX);
    float dY = ToWorldY(mouseY)-ToWorldY(pmouseY);
    xBounds += dX;
    yBounds += dY;
  }
  
  public void Place(float x1, float y1){
    if(draggedElement!=this){
      x=x1; y=y1;
    }
  }
  
  public void DrawSelect(){
    rect(WorldX(),WorldY(),xBounds,yBounds);
  }
  
  public void Reset(){
    xBounds = 0;
    yBounds = 0;
  }
}

Cursor2D cursor = new Cursor2D();

float deleteTimer = 0;
void IncrementDeleteTimer(float x, float y, float w, float h, LogicGate lg){
  deleteTimer += TAU/60.0;
  if(deleteTimer > 0.01f){
    noFill();
    stroke(warningCol);
    strokeWeight(3);
    arc(x,y,2*w,2*w,0,deleteTimer);
    strokeWeight(1);
    fill(255,0,0);
    text("deleting...",x,y+h+10);
  }
  
  if(deleteTimer > TAU){
    deleteTimer = 0;
    DeleteGates(lg);
  }
}

String[] normalActions = {
  "[RMB]+drag: pan view",
  "[LMB]: move 2D cursor",
  "[LMB]+drag: select things",
  "[Shift]+[LMB]+drag: additively select things"
};

String[] gateActions = {
  "[LMB]+drag: move gate(s)",
  "[RMB] hold: delete gate(s)"
};

String[] nodeActions = {
  "[LMB]+drag to another pin: create a link between two pins"
};

String[] selectedActions = {
  "[Shift]+[G]: combine 2+ gates into a group",
  "[Shift]+[D]: duplicate selection"
};

String[] selectedPinActions = {
  "[Shift]+[C]: connect inputs to outputs"
};

String[] selectedInputActions = {
  "[Shift]+[C]: disconnect"
};

float DrawInstructions(String[] actions,float h, float v,float spacing){
    for(int i = actions.length-1; i >= 0; i --){
      String s = actions[i];
      text(s,h,v);
      v+=spacing;
    }
    return v;
}

//will be used by various things for renaming, etc
TextInput textField = new TextInput();
TextLabel fileNameField;  

void DrawAvailableActions(){
  float v = height - 10;
  float h = 0;
  float spacing = -10;
  textAlign(LEFT);
  fill(255,0,0);
  if(selection.size()>0){
    v = DrawInstructions(selectedActions,h,v,spacing);
  }
  fill(0,200,200);
  if((selectedInputs.size()>0)&&(selectedOutputs.size()>0)){
    v = DrawInstructions(selectedPinActions,h,v,spacing);
  } else if(selectedInputs.size()>0){
    v=DrawInstructions(selectedInputActions,h,v,spacing);
  }
  
  fill(foregroundCol);
  if(lastSelectedPin!=null){
    v = DrawInstructions(nodeActions,h,v,spacing);
  } else if(gateUnderMouse!=null){
    fill(255,0,0);
    v = DrawInstructions(gateActions,h,v,spacing);
  } else {
    v = DrawInstructions(normalActions,h,v,spacing);
  }
  textSize(TEXTSIZE+4);
  text("Actions available: ",h,v);
  textSize(TEXTSIZE);
  v+=spacing;
}


void draw(){
  if(gateUnderMouse!=null){
    cursor(MOVE);
  } else {
    noCursor();
  }
  
  //UI space
  dragStarted = false;
  background(backgroundCol);
  fill(foregroundCol);
  stroke(foregroundCol);
  drawCrosshair(mouseX,mouseY,10);
  
  textAlign(LEFT);
  if(numSelected > 0){
    text("Selected gates: "+numSelected+" primitive, "+selection.size()+" groups",0,10);
  }
  if((selectedInputs.size()+selectedOutputs.size())>0){
    text("Selected IO: "+selectedInputs.size()+" input nodes, "+selectedOutputs.size()+" output nodes",0,20);
  }
  
  DrawAvailableActions();
    
  //needs to be manually reset
  mouseOver = false;
  gateUnderMouse = null;
  lastSelectedPin = null;
  
  //World space
  translate(width/2,height/2);
  scale(scale);
  translate(-xPos,-yPos);
  drawCrosshair(0,0,30);
  textAlign(RIGHT);
  text("0,0", -TEXTSIZE,TEXTSIZE);
  
  
  for(int i = circuit.size()-1; i >=0 ;i--){
    LogicGate lGate = circuit.get(i);
    lGate.Draw();
    lGate.UpdateIOPins();
  }
  
  for(UIElement element : menus){
    element.Draw();
  }
  
  if(mousePressed){
    if(mouseButton==RIGHT){
      float xAmount = mouseX-pmouseX;
      float yAmount = mouseY-pmouseY;
      adjustView(-xAmount,-yAmount,0);
      
      if(gateUnderMouse!=null){
        IncrementDeleteTimer(gateUnderMouse.x, gateUnderMouse.y,40,gateUnderMouse.h, gateUnderMouse);
      }
    } else {
      if(!((draggedElement!=null)||(mouseOver))){
        cursor.Place(MouseXPos(),MouseYPos());
        if(!keyDown(ShiftKey)){
          ClearGateSelection();
          ClearPinSelection();
        }
      }
      
      //Object selection logic
      if(draggedElement==cursor){
        noFill();
        cursor.DrawSelect();
        
        //Select gates
        float x1 = cursor.WorldX();
        float y1 = cursor.WorldY();
        float w1 = cursor.xBounds;
        float h1 = cursor.yBounds;
        if(w1<0){
            x1+=w1; w1=-w1;
        }
        if(h1<0){
          y1+=h1; h1=-h1;
        }
        
        for(LogicGate lgate : circuit){
          if(pointInside(lgate.WorldX(),lgate.WorldY(),x1,y1,w1,h1)){
            if(!selection.contains(lgate)){
              selection.add(lgate);
              numSelected+= lgate.NumGates();
            }
          }
          
          //Select pins while looking at this gate
          if(lgate.inputs!=null){
            for(InPin p : lgate.inputs){
              if(pointInside(p.WorldX(), p.WorldY(),x1,y1,w1,h1)){
                if(!selectedInputs.contains(p)){
                  selectedInputs.add(p);
                }
              }
            }
          }
          
          if(lgate.outputs!=null){
            for(OutPin p : lgate.outputs){
              if(pointInside(p.WorldX(), p.WorldY(),x1,y1,w1,h1)){
                if(!selectedOutputs.contains(p)){
                  selectedOutputs.add(p);
                }
              }
            }
          }
        }
      } else {
        cursor.Reset();
      }
    }
  } else {
    deleteTimer = 0;
  }
  
  cursor.Draw();
  
  for(LogicGate lGate : selection){
    stroke(255,0,0);
    drawCrosshair(lGate.WorldX(),lGate.WorldY(),max(10.0/scale,lGate.w));
  }
  
  strokeWeight(2);
  stroke(0,255,255);
  int i = 0;
  for(InPin p : selectedInputs){
    drawArrow(p.WorldX(), p.WorldY(),10,-1,false);
    text(i,p.WorldX(), p.WorldY());
    i++;
  }
  stroke(255,255,0);
  i = 0;
  for(OutPin p : selectedOutputs){
    drawArrow(p.WorldX(), p.WorldY(),10,-1,false);
    text(i,p.WorldX(), p.WorldY());
    i++;
  }
  
  textField.Draw();
  
  strokeWeight(1);
  //handle all key shortcuts
  if(!fileNameField.isTyping){
    String filePath = filepath(fileNameField.Text());
    if(keyDown(ShiftKey)){
      if(keyPushed(GKey)){
        CreateNewGroup();
      } else if(keyPushed(DKey)){
        Duplicate();
      } else if(keyPushed(CKey)){
        ConnectSelected();
      } else if(keyPushed(SKey)){
        SaveProject(filePath);
        println("Saved "+filePath);
      } else if(keyPushed(LKey)){
        LoadProject(filePath);
        println("Loaded "+filePath);
      }
    }
    textAlign(RIGHT);
    text("[Shift]+[S] to save " + filePath ,-20,20);
    text("[Shift]+[L] to load " + filePath ,-20,40);
  }
  
  Cleanup();
}

void drawArrow(float x, float y, float size, int dir, boolean vertical){
  if(vertical){
    line(x,y,x-dir*size,y+dir*size);
    line(x,y,x+dir*size,y+dir*size);
  } else {
    line(x,y,x+dir*size,y+dir*size);
    line(x,y,x+dir*size,y-dir*size);
  }
}

void mouseWheel(MouseEvent e){
  xPos = lerp(xPos,MouseXPos(),0.1*-e.getCount());
  yPos = lerp(yPos,MouseYPos(),0.1*-e.getCount());
  adjustView(0,0,-zoomSpeed*e.getCount());
}

void drawCrosshair(float x,float y, float r){
  line(x-r,y,x+r,y);
  line(x,y-r,x,y+r);
}

float viewSpeed = 5;
float zoomSpeed = 0.2;
void adjustView(float xAmount, float yAmount, float scaleAmount){
  float sensitivity = 1.0/scale;
  xPos+=xAmount*sensitivity;
  yPos+=yAmount*sensitivity;
  scale=constrain(scale+scaleAmount*scale,0.1,10);
}
