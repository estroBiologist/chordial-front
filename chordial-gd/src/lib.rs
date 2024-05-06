use std::{fmt::Write, sync::{Mutex, Arc}, path::PathBuf};

use chordial::{engine::{Engine, Frame}, param::ParamValue, node::BusKind};
use cpal::{traits::{HostTrait, DeviceTrait, StreamTrait}, SupportedBufferSize, StreamConfig, SampleRate, Stream};
use godot::{prelude::*, engine::{FileAccess, ProjectSettings}};

pub struct ChordialGD;

#[gdextension]
unsafe impl ExtensionLibrary for ChordialGD {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct ChordialEngine {
    pub engine: Arc<Mutex<Engine>>,

    #[var(get = get_playing, set = set_playing)]
    #[allow(dead_code)]
    playing: bool,

    #[var(get = get_position, set = set_position)]
    #[allow(dead_code)]
    position: i64,

    #[allow(dead_code)]
    stream: Option<Stream>,

    #[allow(dead_code)]
    base: Base<Node>,
}

#[godot_api]
impl INode for ChordialEngine {
    fn init(base: Base<Node>) -> Self {
        godot_print!("initializing ChordialEngine...");

        let host = cpal::default_host();
        let device = host.default_output_device().expect("no default output device available!");

        godot_print!("using output device `{}`", device.name().unwrap_or("(could not get device name)".to_string()));
        
        godot_print!("\nsupported configurations:\n");

        let preferred_sample_rate = 48000;
        
        let mut sample_rate = 0;

        for config in device.supported_output_configs().unwrap() {
            godot_print!("  sample rate range: ({} - {})", 
                config.min_sample_rate().0,
                config.max_sample_rate().0,
            );

            if sample_rate != preferred_sample_rate {
                let new_sample_rate = preferred_sample_rate.clamp(config.min_sample_rate().0, config.max_sample_rate().0);
                
                if new_sample_rate.abs_diff(preferred_sample_rate) < sample_rate.abs_diff(preferred_sample_rate) {
                    sample_rate = new_sample_rate;
                }
            }
            
            match config.buffer_size() {
                SupportedBufferSize::Range { min, max } => {
                    godot_print!("  buffer size: ({} - {})", min, max);
                }
                SupportedBufferSize::Unknown => {
                    godot_print!("  buffer size: unknown");
                }
            }

            godot_print!("  channels: {}", config.channels());
            godot_print!("");
        }

        let config = StreamConfig {
            channels: 2,
            sample_rate: SampleRate(sample_rate),
            buffer_size: cpal::BufferSize::Fixed(1024),
        };

        let engine = Engine::new(config.sample_rate.0);
        let engine = Arc::new(Mutex::new(engine));
        
        let thread_engine = engine.clone();
        let mut buffer = vec![];

        let stream = device.build_output_stream(
            &config,
    
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                buffer.resize(data.len() / 2, Frame([0f32; 2]));
                thread_engine.lock().unwrap().render(&mut buffer);

                for (i, frame) in buffer.iter().enumerate() {
                    data[i*2] = frame.0[0];
                    data[i*2+1] = frame.0[1];
                }
    
                buffer.fill(Frame([0f32; 2]));
            },
    
            move |_| {
                todo!()
            },
    
            None
        ).unwrap();

        stream.play().unwrap();

        Self {
            engine,
            playing: false,
            position: 0,
            base,
            stream: Some(stream),
        }
    }
}

fn variant_to_param_value(value: Variant) -> ParamValue {
    match value.get_type() {
        VariantType::Float => ParamValue::Float(value.try_to().unwrap()),
        VariantType::Int => ParamValue::Int(value.try_to().unwrap()),
        VariantType::String => ParamValue::String(value.try_to().unwrap()),

        _ => {
            panic!("invalid Variant type for parameter: {:?}", value.get_type())
        }
    }
}

fn param_value_to_variant(value: ParamValue) -> Variant {
    match value {
        ParamValue::String(string) => Variant::from(string.clone()),
        ParamValue::Int(int) => Variant::from(int),
        ParamValue::Float(float) => Variant::from(float)
    }
}

// public api
#[godot_api]
impl ChordialEngine {
    #[func]
    fn get_node_count(&self) -> u64 {
        self.engine.lock().unwrap().get_node_count() as u64
    }

    #[func]
    fn node_get_param_count(&self, node: u64) -> u64 {
        self.engine.lock().unwrap().get_node(node as usize).unwrap().get_params().len() as u64
    }

    #[func]
    fn node_get_param_name(&self, node: u64, param: u64) -> Variant {
        let lock = self.engine.lock().unwrap();
        let node = lock.get_node(node as usize).unwrap();
        
        if let Some((param, _)) = node.get_params().get(param as usize) {
            Variant::from(param.text)
        } else {
            Variant::nil()
        }
    }

    #[func]
    fn node_get_param_value(&self, node: u64, param: u64) -> Variant {
        let lock = self.engine.lock().unwrap();
        let node = lock.get_node(node as usize).unwrap();
        
        if let Some((_, param)) = node.get_params().get(param as usize) {
            param_value_to_variant(param.clone())
        } else {
            Variant::nil()
        }
    }

    #[func]
    fn node_get_input_count(&self, node: u64) -> u64 {
        self.engine.lock().unwrap().get_node(node as usize).unwrap().inputs.len() as u64
    }

    #[func]
    fn node_get_output_count(&self, node: u64) -> u64 {
        self.engine.lock().unwrap().get_node(node as usize).unwrap().outputs.len() as u64
    }

    #[func]
    fn node_get_input_name(&self, node: u64, input: u64) -> String {
        let lock = self.engine.lock().unwrap();
        
        let Some(node) = lock.get_node(node as usize) else {
            return String::new()
        };

        let Some(name) = node.node.get_input_names().get(input as usize) else {
            return String::new()
        };

        name.to_string()
    }

    #[func]
    fn node_get_output_name(&self, node: u64, output: u64) -> String {
        let lock = self.engine.lock().unwrap();
        
        let Some(node) = lock.get_node(node as usize) else {
            return String::new()
        };

        let Some(name) = node.node.get_output_names().get(output as usize) else {
            return String::new()
        };

        name.to_string()
    }

    #[func]
    fn node_get_input_type(&self, node: u64, input: u64) -> i8 {
        match self.engine.lock().unwrap().get_node(node as usize).unwrap().node.get_inputs()[input as usize] {
            BusKind::Audio => 0,
            BusKind::Control => 1,
            BusKind::Midi => 2,
        }
    }

    #[func]
    fn node_get_output_type(&self, node: u64, output: u64) -> i8 {
        match self.engine.lock().unwrap().get_node(node as usize).unwrap().node.get_outputs()[output as usize] {
            BusKind::Audio => 0,
            BusKind::Control => 1,
            BusKind::Midi => 2,
        }
    }

    #[func]
    fn node_get_input_connection(&self, node: u64, input: u64, index: u64) -> Option<Gd<OutputRef>> {
        let lock = self.engine.lock().unwrap();

        if let Some(output_ref) = lock.get_node(node as usize).unwrap().inputs[input as usize].0.get(index as usize) {
            Some(Gd::from_object(OutputRef {
                node: output_ref.node as i64,
                output: output_ref.output as i64
            }))
        } else {
            None
        }
    }

    #[func]
    fn node_get_input_connection_count(&self, node: u64, input: u64) -> i64 {
        self.engine.lock().unwrap().get_node(node as usize).unwrap().inputs[input as usize].0.len() as i64
    }

    #[func]
    fn node_add_input_connection(&mut self, node: u64, input: u64, connection: Gd<OutputRef>) {
        let mut lock = self.engine.lock().unwrap();
        let node = lock.get_node_mut(node as usize).unwrap();
    
        let output_node: u64 = connection.get("node".into()).to();
        let output: u64 = connection.get("output".into()).to();

        node.inputs[input as usize].0.push(chordial::node::OutputRef {
            node: output_node as usize,
            output: output as usize,
        })
    
    }

    #[func]
    fn node_remove_input_connection(&mut self, node: u64, input: u64, connection: Gd<OutputRef>) {
        let mut lock = self.engine.lock().unwrap();
        let node = lock.get_node_mut(node as usize).unwrap();
    
        let output_node: u64 = connection.get("node".into()).to();
        let output: u64 = connection.get("output".into()).to();
        
        let output_ref = chordial::node::OutputRef {
            node: output_node as usize,
            output: output as usize,
        };

        let idx = node.inputs[input as usize].0.iter().position(|elem| elem.node == output_ref.node && elem.output == output_ref.output);

        if let Some(idx) = idx {
            node.inputs[input as usize].0.remove(idx);
        }
    }

    #[func]
    fn node_set_param_value(&self, node: u64, param: u64, value: Variant) {
        let mut lock = self.engine.lock().unwrap();
        let node = lock.get_node_mut(node as usize).unwrap();

        node.set_param(param as usize, variant_to_param_value(value));
    }

    #[func]
    fn node_get_id(&self, node: u64) -> GString {
        let lock = self.engine.lock().unwrap();
        lock.get_node(node as usize).unwrap().id.into_godot()
    }

    #[func]
    fn node_get_name(&self, node: u64) -> GString {
        self.engine.lock().unwrap().get_node(node as usize).unwrap().node.get_name().into_godot()
    }

    #[func]
    fn save_state(&self, mut file: Gd<FileAccess>) {
        file.store_string(self.engine.lock().unwrap().to_string().into_godot());
    }

    #[func]
    fn load_state(&mut self, path: GString) {
        let path = ProjectSettings::singleton().globalize_path(path);
        let mut lock = self.engine.lock().unwrap();

        lock.load_from_file(&PathBuf::from(path.to_string()));
    }

    #[func]
    fn set_position(&mut self, position: i64) {
        self.engine.lock().unwrap().seek(position.max(0) as usize)
    }

    #[func]
    fn get_position(&self) -> i64 {
        self.engine.lock().unwrap().position() as i64
    }

    #[func]
    fn set_playing(&mut self, playing: bool) {
        self.engine.lock().unwrap().playing = playing
    }

    #[func]
    fn get_playing(&self) -> bool {
        self.engine.lock().unwrap().playing
    }

    #[func]
    fn get_constructors(&self) -> PackedStringArray {
        self
            .engine
            .lock()
            .unwrap()
            .constructors()
            .map(|string| string.to_godot())
            .collect()
    }

    #[func]
    fn create_node(&mut self, name: GString) -> u64 {
        self.engine.lock().unwrap().create_node(&name.to_string()) as u64
    }

    #[func]
    fn delete_node(&mut self, node: u64) {
        self.engine.lock().unwrap().delete_node(node as usize);
    }

    #[func]
    fn get_realtime_factor(&self) -> f32 {
        let lock = self.engine.lock().unwrap();
        lock.dbg_process_time / lock.dbg_buffer_time
    }

    #[func]
    fn to_string(&self) -> String {
        let mut result = String::new();

        write!(result, "{}", &*self.engine.lock().unwrap()).unwrap();
        result
    }

    #[func]
    fn get_debug_info(&self) -> String {
        self.engine.lock().unwrap().get_debug_info()
    }
}


#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct OutputRef {
    #[export]
    pub node: i64,
    #[export]
    pub output: i64,
}

#[godot_api]
impl IRefCounted for OutputRef {
    fn init(_base: Base<RefCounted>) -> Self {
        OutputRef {
            node: 0,
            output: 0,
        }
    }
}

#[godot_api]
impl OutputRef { }
