package cl.duoc.mi_foro_usuarios.service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import cl.duoc.mi_foro_usuarios.Constants;
import cl.duoc.mi_foro_usuarios.dto.LoginRequestDTO;
import cl.duoc.mi_foro_usuarios.dto.LoginResponseDTO;
import cl.duoc.mi_foro_usuarios.dto.UsuarioRequestDTO;
import cl.duoc.mi_foro_usuarios.dto.UsuarioRequestOptionalDTO;
import cl.duoc.mi_foro_usuarios.dto.UsuarioResponseDTO;
import cl.duoc.mi_foro_usuarios.entity.TipoUsuarioEntity;
import cl.duoc.mi_foro_usuarios.entity.UsuarioEntity;
import cl.duoc.mi_foro_usuarios.jwt.JwtUtil;
import cl.duoc.mi_foro_usuarios.repository.TipoUsuarioRespository;
import cl.duoc.mi_foro_usuarios.repository.UsuarioRepository;
import jakarta.servlet.http.HttpServletRequest;


@Service 
public class UsuarioService {

    private final PasswordEncoder passwordEncoder;
    private final TipoUsuarioRespository tipoUsuarioRespository;
    private final UsuarioRepository usuarioRepository;

    private final AuthenticationManager authenticationManager;
    private final JwtUtil jwtUtil;


    public UsuarioService(
        UsuarioRepository usuarioRepository, TipoUsuarioRespository tipoUsuarioRespository,
        AuthenticationManager authenticationManager, JwtUtil jwtUtil, PasswordEncoder passwordEncoder
    ) {
        this.usuarioRepository = usuarioRepository;
        this.tipoUsuarioRespository = tipoUsuarioRespository;

        this.authenticationManager = authenticationManager;
        this.jwtUtil = jwtUtil;
        this.passwordEncoder = passwordEncoder;
    }


    // get
    public ApiResponse<List<UsuarioResponseDTO>> getUsuarios() {
        List<UsuarioResponseDTO> usuarios = usuarioRepository.findAll().stream().map(this::toDTO).toList();
        return new ApiResponse<>(HttpStatus.OK, usuarios);
    }


    // get id
    public ApiResponse<?> getUsuarioById(Long id) {
        Optional<UsuarioEntity> usuario = usuarioRepository.findById(id);
        if(usuario.isEmpty()) {
            return new ApiResponse<>(HttpStatus.NOT_FOUND, List.of("Usuario no encontrado"));
        }
        return new ApiResponse<>(HttpStatus.OK, usuario.map(this::toDTO));
    }


    // do
    public ApiResponse<?> doUsuario(UsuarioRequestDTO usuarioRequest) {

        // lista errores
        List<String> errores = new ArrayList<>();

        String nUsuario     = usuarioRequest.getUsuario();
        String password     = usuarioRequest.getPassword();
        String nombre       = usuarioRequest.getNombre();
        String correo       = usuarioRequest.getCorreo();
        Long tipoUsuarioId  = usuarioRequest.getTipoUsuarioId();

        if(nUsuario != null && nUsuario.isEmpty()) {
            errores.add("Nombre de usuario no puede estar vacío");
        } else if(usuarioRepository.existsByUsuario(nUsuario)) {
            errores.add("El usuario ya está registrado");
        }

        if(password != null && password.isEmpty()) errores.add("Contraseña no puede estar vacío");
        if(nombre != null && nombre.isEmpty()) errores.add("Nombre no puede estar vacío");
        if(correo != null && correo.isEmpty()) errores.add("Correo no puede estar vacío");
        
        Optional<TipoUsuarioEntity> tipoUsuarioOpt = tipoUsuarioRespository.findById(tipoUsuarioId);
        if(tipoUsuarioOpt.isEmpty()) {
            errores.add("Tipo de usuario no encontrado");
        }

        if(!errores.isEmpty()) {
            return new ApiResponse<>(HttpStatus.BAD_REQUEST, errores);
        }

        TipoUsuarioEntity tipoUsuario = tipoUsuarioOpt.get();
        
        UsuarioEntity usuario = new UsuarioEntity();

        usuario.setUsuario(usuarioRequest.getUsuario());
        usuario.setPassword(passwordEncoder.encode(usuarioRequest.getPassword()));
        usuario.setNombre(usuarioRequest.getNombre());
        usuario.setCorreo(usuarioRequest.getCorreo());
        usuario.setFecha(LocalDateTime.now());
        usuario.setTipoUsuario(tipoUsuario);
        usuario.setActivo(1);

        UsuarioEntity createdUsuario = usuarioRepository.save(usuario);
        return new ApiResponse<>(HttpStatus.CREATED, List.of(toDTO(createdUsuario)));
    }


    // set
    public ApiResponse<?> setUsuario(Long id, UsuarioRequestOptionalDTO usuarioRequest, HttpServletRequest httpRequest) {
        // solo puede actualizar un admin o el mismo usuario logueado
        String token = httpRequest.getHeader(Constants.HEADER_AUTHORIZATION_KEY).substring(Constants.TOKEN_BEARER_PREFIX.length());

        boolean esAdmin = "ROLE_ADMIN".equals(jwtUtil.extractRole(token));
        Long usuarioAutenticadoId = jwtUtil.extractUserId(token);
        boolean esMismoUsuario = usuarioAutenticadoId.equals(id);

        if(!esAdmin && !esMismoUsuario) {
            return new ApiResponse<>(HttpStatus.FORBIDDEN, List.of("No tienes permiso para modificar este usuario"));
        }

        String nUsuario     = usuarioRequest.getUsuario();
        String password     = usuarioRequest.getPassword();
        String nombre       = usuarioRequest.getNombre();
        String correo       = usuarioRequest.getCorreo();
        Long tipoUsuarioId  = usuarioRequest.getTipoUsuarioId();
        Boolean activo      = usuarioRequest.getActivo();

        if(
            nUsuario        == null &&
            password        == null && 
            nombre          == null && 
            correo          == null &&
            tipoUsuarioId   == null &&
            activo          == null
        ) {
            return new ApiResponse<>(HttpStatus.CONFLICT, List.of("No hay datos para actualizar"));
        }
        
        
        Optional<UsuarioEntity> usuarioOptional = usuarioRepository.findById(id);
        if(usuarioOptional.isEmpty()) {
            return new ApiResponse<>(HttpStatus.NOT_FOUND, List.of("Usuario no encontrado"));
        }
        

        UsuarioEntity usuario = usuarioOptional.get();

        // lista errores
        List<String> errores = new ArrayList<>();
        
        if(nUsuario != null && nUsuario.isEmpty()) {
            errores.add("Nombre de usuario no puede estar vacío");
        } else if(usuarioRepository.existsByUsuario(nUsuario)) {
            errores.add("El usuario ya está registrado");
        }
        
        if(password != null && password.isEmpty()) errores.add("Contraseña no puede estar vacío");
        if(nombre != null && nombre.isEmpty()) errores.add("Nombre no puede estar vacío");
        if(correo != null && correo.isEmpty()) errores.add("Correo no puede estar vacío");
        
        TipoUsuarioEntity tipoUsuario = null;
        if(tipoUsuarioId != null) {
            Optional<TipoUsuarioEntity> tipoUsuarioOpt = tipoUsuarioRespository.findById(tipoUsuarioId);
            tipoUsuario = tipoUsuarioOpt.orElse(null);
            if(tipoUsuario == null) errores.add("Tipo de usuario no encontrado");
        }
        
        if(!errores.isEmpty()) {
            return new ApiResponse<>(HttpStatus.BAD_REQUEST, errores);
        }
        

        if(nUsuario != null) usuario.setUsuario(nUsuario);
        if(password != null) usuario.setPassword(passwordEncoder.encode(password));
        if(nombre != null) usuario.setNombre(nombre);
        if(correo != null) usuario.setCorreo(correo);
        if(tipoUsuario != null) usuario.setTipoUsuario(tipoUsuario);
        if(activo != null) usuario.setActivo(activo ? 1 : 0);

        UsuarioEntity savedUsuario = usuarioRepository.save(usuario);
        return new ApiResponse<>(HttpStatus.OK, List.of(toDTO(savedUsuario)));
    }


    // delete
    public ApiResponse<?> deletedUsuario(Long id) {
        Optional<UsuarioEntity> usuarioOptional = usuarioRepository.findById(id);
        if(usuarioOptional.isEmpty()) {
            return new ApiResponse<>(HttpStatus.NOT_FOUND, List.of("Usuario no encontrado"));
        }

        usuarioRepository.deleteById(id);
        return new ApiResponse<>(HttpStatus.OK, List.of("Usuario eliminado"));
    }


    public LoginResponseDTO login(LoginRequestDTO data) {
        Authentication authentication = authenticationManager.authenticate(new UsernamePasswordAuthenticationToken(data.getUsuario(), data.getPassword()));

        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        UsuarioEntity usuario = usuarioRepository.findByUsuario(userDetails.getUsername()).orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado"));
        String role = userDetails.getAuthorities().iterator().next().getAuthority();
        String token = jwtUtil.generateToken(usuario.getId(), userDetails.getUsername(), role);

        return new LoginResponseDTO(token, "Bearer");
    }




    private UsuarioResponseDTO toDTO(UsuarioEntity usuario) {
        return new UsuarioResponseDTO(
            usuario.getId(),
            usuario.getUsuario(),
            // usuario.getPassword(),
            usuario.getNombre(),
            usuario.getCorreo(),
            usuario.getTipoUsuario().getId(),
            usuario.getActivo()
        );
    }
}

