export function createOtpInput({
  container,
  valueInput,
  length=6,
  onChange=()=>{}
}={}){
  if(!container||!valueInput)throw new Error("otp_input_target_missing");

  const inputs=[];
  container.replaceChildren();

  function digits(value){
    return String(value||"").replace(/\D/g,"").slice(0,length);
  }

  function syncValue({notify=true}={}){
    valueInput.value=inputs.map(input=>input.value).join("");
    container.classList.toggle("is-complete",valueInput.value.length===length);
    if(notify)onChange(valueInput.value);
  }

  function distribute(value,startIndex=0){
    const clean=digits(value);
    if(!clean)return;

    let index=startIndex;
    for(const digit of clean){
      if(index>=length)break;
      inputs[index].value=digit;
      index+=1;
    }
    syncValue();

    const next=Math.min(index,length-1);
    inputs[next]?.focus();
    inputs[next]?.select();
  }

  for(let index=0;index<length;index+=1){
    const input=document.createElement("input");
    input.type="text";
    input.inputMode="numeric";
    input.pattern="[0-9]*";
    input.maxLength=1;
    input.autocomplete=index===0?"one-time-code":"off";
    input.className="mfa-code-digit";
    input.setAttribute("aria-label",`Dígito ${index+1} de ${length}`);
    input.dataset.otpIndex=String(index);

    input.addEventListener("input",()=>{
      const raw=String(input.value||"").replace(/\D/g,"");
      if(raw.length>1){
        input.value="";
        distribute(raw,index);
        return;
      }
      input.value=raw.slice(-1);
      syncValue();
      if(input.value&&index<length-1){
        inputs[index+1].focus();
        inputs[index+1].select();
      }
    });

    input.addEventListener("keydown",event=>{
      if(event.key==="Backspace"){
        if(input.value){
          input.value="";
          syncValue();
          event.preventDefault();
          return;
        }
        if(index>0){
          inputs[index-1].value="";
          syncValue();
          inputs[index-1].focus();
          event.preventDefault();
        }
        return;
      }
      if(event.key==="ArrowLeft"&&index>0){
        inputs[index-1].focus();
        event.preventDefault();
      }else if(event.key==="ArrowRight"&&index<length-1){
        inputs[index+1].focus();
        event.preventDefault();
      }
    });

    input.addEventListener("focus",()=>input.select());

    input.addEventListener("paste",event=>{
      const pasted=digits(event.clipboardData?.getData("text")||"");
      if(!pasted)return;
      event.preventDefault();
      distribute(pasted,index);
    });

    inputs.push(input);
    container.append(input);
  }

  container.addEventListener("click",event=>{
    if(event.target!==container)return;
    const firstEmpty=inputs.findIndex(input=>!input.value);
    inputs[firstEmpty<0?length-1:firstEmpty]?.focus();
  });

  function setValue(value,{notify=true}={}){
    const clean=digits(value);
    inputs.forEach((input,index)=>{input.value=clean[index]||"";});
    syncValue({notify});
  }

  function setDisabled(disabled){
    inputs.forEach(input=>{input.disabled=Boolean(disabled);});
    container.classList.toggle("is-disabled",Boolean(disabled));
  }

  function focus(){
    const firstEmpty=inputs.findIndex(input=>!input.value);
    const index=firstEmpty<0?length-1:firstEmpty;
    inputs[index]?.focus();
    inputs[index]?.select();
  }

  function clear({notify=true}={}){
    setValue("",{notify});
  }

  setValue(valueInput.value,{notify:false});

  return {inputs,setValue,setDisabled,focus,clear};
}
